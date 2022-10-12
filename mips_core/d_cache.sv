/*
 * d_cache.sv
 * Author: Zinsser Zhang
 * Last Revision: 03/13/2022
 *
 * This is a direct-mapped data cache. Line size and depth (number of lines) are
 * set via INDEX_WIDTH and BLOCK_OFFSET_WIDTH parameters. Notice that line size
 * means number of words (each consist of 32 bit) in a line. Because all
 * addresses in mips_core are 26 byte addresses, so the sum of TAG_WIDTH,
 * INDEX_WIDTH and BLOCK_OFFSET_WIDTH is `ADDR_WIDTH - 2.
 *
 * Typical line sizes are from 2 words to 8 words. The memory interfaces only
 * support up to 8 words line size.
 *
 * Because we need a hit latency of 1 cycle, we need an asynchronous read port,
 * i.e. data is ready during the same cycle when address is calculated. However,
 * SRAMs only support synchronous read, i.e. data is ready the cycle after the
 * address is calculated. Due to this conflict, we need to read from the banks
 * on the clock edge at the beginning of the cycle. As a result, we need both
 * the registered version of address and a non-registered version of address
 * (which will effectively be registered in SRAM).
 *
 * See wiki page "Synchronous Caches" for details.
 */
`include "mips_core.svh"

interface d_cache_input_ifc ();
	logic valid;
	mips_core_pkg::MemAccessType mem_action;
	logic [`ADDR_WIDTH - 1 : 0] addr;
	logic [`ADDR_WIDTH - 1 : 0] addr_next;
	logic [`ADDR_WIDTH - 1 : 0] pc; 
	logic [`DATA_WIDTH - 1 : 0] data;

	modport in  (input valid, mem_action, addr, addr_next, data, pc);
	modport out (output valid, mem_action, addr, addr_next, data, pc);
endinterface

module d_cache #(
	parameter REQ_INDEX_WIDTH = 5,
	parameter BLOCK_OFFSET_WIDTH = 2,
	parameter ASSOCIATIVITY = 8, 
	parameter VICTIM_CACHE_SIZE = 32
	)(
	// General signals
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	d_cache_input_ifc.in in,

	// Response
	cache_output_ifc.out out,

	// AXI interfaces
	axi_write_address.master mem_write_address,
	axi_write_data.master mem_write_data,
	axi_write_response.master mem_write_response,
	axi_read_address.master mem_read_address,
	axi_read_data.master mem_read_data
); 
	localparam SET_SIZE = ASSOCIATIVITY > 1 ? $clog2(ASSOCIATIVITY) : 1;
	localparam VICTIM_CACHE_SIZE_INDEX = $clog2(VICTIM_CACHE_SIZE);
	localparam INDEX_WIDTH = REQ_INDEX_WIDTH - $clog2(ASSOCIATIVITY); 
	localparam TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - BLOCK_OFFSET_WIDTH - 2;
	localparam LINE_SIZE = 1 << BLOCK_OFFSET_WIDTH;
	localparam DEPTH = 1 << INDEX_WIDTH;

	// Check if the parameters are set correctly
	generate
		if(TAG_WIDTH <= 0 || LINE_SIZE >= 16 || (ASSOCIATIVITY != 1 && ASSOCIATIVITY != 2 && ASSOCIATIVITY != 4 && ASSOCIATIVITY != 8 && ASSOCIATIVITY != 16))
		begin
			INVALID_D_CACHE_PARAM invalid_d_cache_param ();
		end
	endgenerate

	// Parsing
	logic [TAG_WIDTH - 1 : 0] i_tag;
	logic [INDEX_WIDTH - 1 : 0] i_index;
	logic [BLOCK_OFFSET_WIDTH - 1 : 0] i_block_offset;

	logic [INDEX_WIDTH - 1 : 0] i_index_next;

	assign {i_tag, i_index, i_block_offset} = in.addr[`ADDR_WIDTH - 1 : 2];
	assign i_index_next = in.addr_next[BLOCK_OFFSET_WIDTH + 2 +: INDEX_WIDTH];
	// Above line uses +: slice, a feature of SystemVerilog
	// See https://stackoverflow.com/questions/18067571

	// States
	enum logic [2:0] {
		STATE_READY,            // Ready for incoming requests
		STATE_FLUSH_REQUEST,    // Sending out memory write request
		STATE_FLUSH_DATA,       // Writes out a dirty cache line
		STATE_REFILL_REQUEST,   // Sending out memory read request
		STATE_VICTIM_HIT,	// Puts victim hit line into temp for swapping
		STATE_VICTIM_SWAP_1,	// Loads the evicted cache line into victim & loads the temp to override cache
		STATE_VICTIM_SWAP_2,	// Loads the evicted cache line into victim & loads the temp to override cache
		STATE_REFILL_DATA       // Loads a cache line from memory
	} state, next_state;
	logic pending_write_response;

	// Registers for flushing and refilling
	logic [INDEX_WIDTH - 1:0] r_index;
	logic [TAG_WIDTH - 1:0] r_tag;

	// databank signals
	logic [LINE_SIZE - 1 : 0] databank_select [ASSOCIATIVITY];
	logic [LINE_SIZE - 1 : 0] databank_we [ASSOCIATIVITY];
	logic [`DATA_WIDTH - 1 : 0] databank_wdata [ASSOCIATIVITY];
	logic [INDEX_WIDTH - 1 : 0] databank_waddr [ASSOCIATIVITY];
	logic [INDEX_WIDTH - 1 : 0] databank_raddr [ASSOCIATIVITY];
	logic [`DATA_WIDTH - 1 : 0] databank_rdata [ASSOCIATIVITY][LINE_SIZE];

	// databanks
	genvar g,i;
	generate
		for (i = 0; i < ASSOCIATIVITY; i++)
		begin : sets_data
			for (g = 0; g < LINE_SIZE; g++)
			begin : databanks
				cache_bank #(
					.DATA_WIDTH (`DATA_WIDTH),
					.ADDR_WIDTH (INDEX_WIDTH)
				) databank (
					.clk,
					.i_we (databank_we[i][g]),
					.i_wdata(databank_wdata[i]),
					.i_waddr(databank_waddr[i]),
					.i_raddr(databank_raddr[i]),

					.o_rdata(databank_rdata[i][g])
				);
			end
		end
	endgenerate

	

	// tagbank signals
	logic tagbank_we [ASSOCIATIVITY];
	logic [TAG_WIDTH - 1 : 0] tagbank_wdata [ASSOCIATIVITY];
	logic [INDEX_WIDTH - 1 : 0] tagbank_waddr [ASSOCIATIVITY];
	logic [INDEX_WIDTH - 1 : 0] tagbank_raddr [ASSOCIATIVITY];
	logic [TAG_WIDTH - 1 : 0] tagbank_rdata [ASSOCIATIVITY];

	genvar j; 
	generate
		for (j = 0; j < ASSOCIATIVITY; j++)
		begin : sets_tags
			cache_bank #(
				.DATA_WIDTH (TAG_WIDTH),
				.ADDR_WIDTH (INDEX_WIDTH)
			) tagbank (
				.clk,
				.i_we    (tagbank_we[j]),
				.i_wdata (tagbank_wdata[j]),
				.i_waddr (tagbank_waddr[j]),
				.i_raddr (tagbank_raddr[j]),

				.o_rdata (tagbank_rdata[j])
			);
		end
	endgenerate
	
	// Victim Cache Storage
	logic [$clog2(LINE_SIZE) - 1 : 0] v_we;
	logic [TAG_WIDTH - 1 : 0] vtagbank [VICTIM_CACHE_SIZE];
	logic [`DATA_WIDTH - 1 : 0] vdatabank [VICTIM_CACHE_SIZE][LINE_SIZE];
	logic [`DATA_WIDTH - 1 : 0] tempdata [LINE_SIZE];
	logic [TAG_WIDTH - 1 : 0] temptag;
	logic [INDEX_WIDTH - 1 : 0] vindexbank [VICTIM_CACHE_SIZE];
	logic [VICTIM_CACHE_SIZE_INDEX - 1 : 0] lru_index;
	logic [VICTIM_CACHE_SIZE_INDEX - 1 : 0] vhit_index;
	logic [VICTIM_CACHE_SIZE_INDEX - 1 : 0] v_index;
	logic [VICTIM_CACHE_SIZE - 1: 0] valid_v;
	logic vhit;
	logic temphit;
	logic tempvalid;
	logic [INDEX_WIDTH - 1 : 0] tempindex;
	logic tempdone;
	logic swap1done;
	logic replacedone;
	logic [VICTIM_CACHE_SIZE_INDEX - 1 : 0] v_ind;
	logic [VICTIM_CACHE_SIZE - 1 : 0] cmp_vhit; 


	// Valid bits
	logic [DEPTH - 1 : 0] valid_bits [ASSOCIATIVITY];
	// Dirty bits
	logic [DEPTH - 1 : 0] dirty_bits [ASSOCIATIVITY];

	// Shift registers for flushing
	logic [`DATA_WIDTH - 1 : 0] shift_rdata[LINE_SIZE];

	// Intermediate signals
	logic valid_way; 
	logic [ASSOCIATIVITY - 1 : 0] tag_cmp; 
	logic [ASSOCIATIVITY - 1 : 0] hit_cmp; 

	logic [SET_SIZE - 1 : 0] hit_way; 
	logic [SET_SIZE - 1 : 0] match_way; 
	logic [SET_SIZE - 1 : 0] evict_way; 

	logic hit, miss;
	logic last_flush_word;
	logic last_refill_word;
	logic last_temp_word;
	logic last_vict_word;
	logic last_swap_word;

	logic mem_halt; 
	logic mem_access; 

	logic policy_1; 
	logic policy_2; 
	logic follower; 

	always_comb
	begin
		mem_access = 1'b0; 
		if (in.valid & miss & !mem_halt) 
		begin
			mem_access = 1'b1; 
		end
		else if (in.valid & hit)
		begin
			mem_access = 1'b1; 
		end
	end

	always_ff @(posedge clk)
	begin
		if (!rst_n)
		begin
			mem_halt <= 1'b0;
		end
		else 
		begin
			if (in.valid & miss) mem_halt <= 1'b1; 
			else mem_halt <= 1'b0; 
		end
	end


	always_comb
	begin
		for (int i = 0; i < ASSOCIATIVITY; i++) 
		begin
			tag_cmp[i] = (i_tag == tagbank_rdata[i]); 
			hit_cmp[i] = valid_bits[i][i_index] && (i_tag == tagbank_rdata[i]); 
		end

		for (int i = 0; i < VICTIM_CACHE_SIZE; i++)
		begin
			cmp_vhit[i] = ((i_tag == vtagbank[i]) && valid_v[i] && (i_index == vindexbank[i])); 
		end
	end

	priority_encoder# (
		.m(ASSOCIATIVITY),
		.n(SET_SIZE)
	) hit_way_retriever (
		.x(hit_cmp),
		.bottom_up(1'b1),
		.valid_in(valid_way),
		.y(hit_way)
	); 

	priority_encoder# (
		.m(VICTIM_CACHE_SIZE),
		.n(VICTIM_CACHE_SIZE_INDEX)
	) vhit_retriever (
		.x(cmp_vhit),
		.bottom_up(1'b0),
		.valid_in(vhit),
		.y(vhit_index)
	); 

	always_comb
	begin
		hit = in.valid
			& |tag_cmp
			& valid_way
			& (state == STATE_READY);
		miss = in.valid & ~hit;

		v_index = vhit ? vhit_index : lru_index;
		temphit = (r_tag == temptag) && tempvalid && tempindex == r_index;
	end

	set_dueling #(
		.ASSOCIATIVITY (ASSOCIATIVITY), 
		.SET_SIZE (SET_SIZE),
		.INDEX_WIDTH (INDEX_WIDTH), 
		.DEPTH (DEPTH)
	) d_cache_set_duel(
		.clk, 
		.rst_n,
		.pc(in.pc), 
		.valid(in.valid),
		.hit,
		.miss,
		.halt(mem_halt),
		.i_index,
		.hit_way,

		.evict_way,
		.policy_1,
		.policy_2,
		.follower
	);

	always_comb
	begin
		if (hit) match_way = hit_way; 
		else if (miss) match_way = evict_way; 
		else match_way = 0;  

		last_flush_word = databank_select[match_way][LINE_SIZE - 1] & mem_write_data.WVALID;
		last_refill_word = databank_select[match_way][LINE_SIZE - 1] & (mem_read_data.RVALID);
		last_temp_word = tempdone & (state == STATE_VICTIM_HIT);
		last_vict_word = swap1done & (state == STATE_VICTIM_SWAP_1);
		last_swap_word = databank_select[match_way][LINE_SIZE - 1] & (state == STATE_VICTIM_SWAP_2);
	end
	
	always_comb
	begin
		mem_write_address.AWVALID = state == STATE_FLUSH_REQUEST;
		mem_write_address.AWID = 0;
		mem_write_address.AWLEN = LINE_SIZE;
		mem_write_address.AWADDR = {tagbank_rdata[match_way], i_index, {BLOCK_OFFSET_WIDTH + 2{1'b0}}};
		mem_write_data.WVALID = state == STATE_FLUSH_DATA;
		mem_write_data.WID = 0;
		mem_write_data.WDATA = shift_rdata[0];
		mem_write_data.WLAST = last_flush_word;

		// Always ready to consume write response
		mem_write_response.BREADY = 1'b1;
	end

	always_comb begin
		mem_read_address.ARADDR = {r_tag, r_index, {BLOCK_OFFSET_WIDTH + 2{1'b0}}};
		mem_read_address.ARLEN = LINE_SIZE;
		mem_read_address.ARVALID = state == STATE_REFILL_REQUEST;
		mem_read_address.ARID = 4'd1;

		// Always ready to consume data
		mem_read_data.RREADY = 1'b1;
	end

	always_comb
	begin
		databank_we[match_way] = '0;
		if (mem_read_data.RVALID)				// We are refilling data
			databank_we[match_way] = databank_select[match_way];
		else if (state == STATE_VICTIM_SWAP_2)
			databank_we[match_way] = databank_select[match_way];
		else if (hit & (in.mem_action == WRITE))	// We are storing a word
			databank_we[match_way][i_block_offset] = 1'b1;
	end

	always_comb
	begin
		if (state == STATE_READY)
		begin
			databank_wdata[match_way] = in.data; 
			databank_waddr[match_way] = i_index;	
			if (next_state == STATE_FLUSH_REQUEST)
				for (int i = 0; i < ASSOCIATIVITY; i++) databank_raddr[i] = i_index;
			else
				for (int i = 0; i < ASSOCIATIVITY; i++) databank_raddr[i] = i_index_next;
		end
		else
		begin
			if (state == STATE_VICTIM_SWAP_2)
				databank_wdata[match_way] = tempdata[v_we];
			else
				databank_wdata[match_way] = mem_read_data.RDATA; 
			databank_waddr[match_way] = r_index;
			if (next_state == STATE_READY)
				for (int i = 0; i < ASSOCIATIVITY; i++) databank_raddr[i] = i_index_next;
			else
				for (int i = 0; i < ASSOCIATIVITY; i++) databank_raddr[i] = r_index;
		end
	end

	always_comb
	begin
		tagbank_we[match_way] = last_refill_word | last_swap_word;
		tagbank_wdata[match_way] = temphit ? temptag : r_tag; 
		tagbank_waddr[match_way] = r_index; 
		tagbank_raddr[match_way] = i_index_next; // ??
		for (int i = 0; i < ASSOCIATIVITY; i++) tagbank_raddr[i] = i_index_next;
	end

	always_comb
	begin
		out.valid = hit;
		out.data = databank_rdata[match_way][i_block_offset];
	end

	always_comb
	begin
		next_state = state;
		unique case (state)
			STATE_READY:
				if (miss)
					if (valid_bits[match_way][i_index] & dirty_bits[match_way][i_index])
						next_state = STATE_FLUSH_REQUEST;
					else
						if(vhit)
							next_state = STATE_VICTIM_HIT;
						else
							next_state = STATE_REFILL_REQUEST;

			STATE_FLUSH_REQUEST:
				if (mem_write_address.AWREADY)
					next_state = STATE_FLUSH_DATA;

			STATE_FLUSH_DATA:
				if (last_flush_word && mem_write_data.WREADY)
					if(vhit)
						next_state = STATE_VICTIM_HIT;
					else
						next_state = STATE_REFILL_REQUEST;

			STATE_VICTIM_HIT:
				if (last_temp_word)
					next_state = STATE_VICTIM_SWAP_1;

			STATE_VICTIM_SWAP_1:
				if (last_vict_word)
					next_state = STATE_VICTIM_SWAP_2;
				
			STATE_VICTIM_SWAP_2:
				if (last_swap_word)
					next_state = STATE_READY;

			STATE_REFILL_REQUEST:
				if (mem_read_address.ARREADY)
					next_state = STATE_REFILL_DATA;
			
			STATE_REFILL_DATA:
				if (last_refill_word)
					next_state = STATE_READY;
		endcase
	end

	always_ff @(posedge clk) begin
		if (~rst_n)
			pending_write_response <= 1'b0;
		else if (mem_write_address.AWVALID && mem_write_address.AWREADY)
			pending_write_response <= 1'b1;
		else if (mem_write_response.BVALID && mem_write_response.BREADY)
			pending_write_response <= 1'b0;
	end

	always_ff @(posedge clk)
	begin
		if (state == STATE_FLUSH_DATA && mem_write_data.WREADY)
			for (int i = 0; i < LINE_SIZE - 1; i++)
				shift_rdata[i] <= shift_rdata[i+1];

		if (state == STATE_FLUSH_REQUEST && next_state == STATE_FLUSH_DATA)
			for (int i = 0; i < LINE_SIZE; i++)
				shift_rdata[i] <= databank_rdata[match_way][i]; 
	end

	always_ff @(posedge clk)
	begin
		if(~rst_n)
		begin
			state <= STATE_READY;
			for (int i = 0; i < ASSOCIATIVITY; i++) 
			begin
				databank_select[i] <= 1;
				valid_bits[i] <= '0;
			end
			valid_v <= '0;
			lru_index <= '0;
		end
		else
		begin
			state <= next_state;

			case (state)
				STATE_READY:
				begin
					for (int i = 0; i < LINE_SIZE; i++) tempdata[i] <= '0;
					temptag <= '0;
					tempindex <= '0;
					tempvalid <= '0;
					v_we <= '0;
					tempdone <= 1'b0;
					swap1done <= 1'b0;
					replacedone <= 1'b0;
					if (miss)
					begin
						r_tag <= i_tag; 
						r_index <= i_index; 
					end
					else if (in.mem_action == WRITE)
						dirty_bits[match_way][i_index] <= 1'b1; //?
				end

				STATE_FLUSH_DATA:
				begin
					if (mem_write_data.WREADY)
							databank_select[match_way] <= {databank_select[match_way][LINE_SIZE - 2 : 0],
								databank_select[match_way][LINE_SIZE - 1]};
				end
				STATE_VICTIM_HIT:
				begin
					temptag <= vtagbank[v_index];
					tempvalid <= valid_v[v_index];
					tempindex <= vindexbank[v_index];
					for(int i = 0; i < LINE_SIZE; i++) tempdata[i] <= vdatabank[v_index][i];
					tempdone <= 1'b1;
					v_ind <= v_index;
				end
				STATE_VICTIM_SWAP_1:
				begin
					vtagbank[v_ind] <= tagbank_rdata[match_way];
					vindexbank[v_ind] <= databank_raddr[match_way];
					valid_v[v_ind] <= 1'b1;
					v_we <= '0;
					for(int i = 0; i < LINE_SIZE; i++) vdatabank[v_ind][i] <= databank_rdata[match_way][i];
					swap1done <= 1'b1;
				end
				STATE_VICTIM_SWAP_2:
				begin
					v_we <= v_we + 1;
					databank_select[match_way] <= {databank_select[match_way][LINE_SIZE - 2 : 0],
						databank_select[match_way][LINE_SIZE - 1]};
					if (last_swap_word)
					begin
						valid_bits[match_way][r_index] <= 1'b1;
						dirty_bits[match_way][r_index] <= 1'b0;
					end

				end
				STATE_REFILL_DATA:
				begin
					if (mem_read_data.RVALID)
						databank_select[match_way] <= {databank_select[match_way][LINE_SIZE - 2 : 0],
							databank_select[match_way][LINE_SIZE - 1]};
					if (valid_bits[match_way][r_index] & !replacedone)
					begin
						for(int i = 0; i < LINE_SIZE;i++) vdatabank[v_index][i] <= databank_rdata[match_way][i];
						vtagbank[v_index] <= tagbank_rdata[match_way];
						vindexbank[v_index] <= databank_raddr[match_way];
						valid_v[v_index] <= 1'b1;
						lru_index <= lru_index + 1;
						valid_bits[match_way][r_index] <= 1'b0;
						replacedone <= 1'b1;
					end

					if (last_refill_word)
					begin
						valid_bits[match_way][r_index] <= 1'b1;
						dirty_bits[match_way][r_index] <= 1'b0;
					end
				end
			endcase
		end
	end


	`ifdef SIMULATION
		logic  counter_hit [ASSOCIATIVITY]; 
		logic  counter_miss [ASSOCIATIVITY]; 

		always_comb 
		begin
			counter_hit = '{default: 1'b0};
			counter_miss = '{default: 1'b0};
			if (mem_access && hit) counter_hit[hit_way] = 1'b1; 
			else if (mem_access && miss) counter_miss[evict_way] = 1'b1; 

		end



		always_ff @(posedge clk)
		begin
			if (rst_n && in.valid)
			begin
				if (hit || miss && !mem_halt)
				begin
					if (follower)
					begin
						if (policy_1) stats_event("Follower_Policy_1"); 
						else stats_event("Follower_Policy_2"); 
					end
					else if (policy_1)
						stats_event("Main_Policy_1"); 
					else 
						stats_event("Main_Policy_2");
				end
				if (mem_access & hit) stats_event("Mem_hit");
				else if (mem_access & miss) stats_event("Mem_miss");

				if (state == STATE_VICTIM_HIT) stats_event("Victim Hit");
				
				if (hit && counter_hit[0]) stats_event("way_1_hit");
				else if (miss && counter_miss[0]) stats_event("way_1_evicted");
				else if (hit && counter_hit[1]) stats_event("way_2_hit");
				else if (miss && counter_miss[1]) stats_event("way_2_evicted");
				else if (hit && counter_hit[2]) stats_event("way_3_hit");
				else if (miss && counter_miss[2]) stats_event("way_3_evicted");
				else if (hit && counter_hit[3]) stats_event("way_4_hit");
				else if (miss && counter_miss[3]) stats_event("way_4_evicted");
				else if (hit && counter_hit[4]) stats_event("way_5_hit");
				else if (miss && counter_miss[4]) stats_event("way_5_evicted");
				else if (hit && counter_hit[5]) stats_event("way_6_hit");
				else if (miss && counter_miss[5]) stats_event("way_6_evicted");
				else if (hit && counter_hit[6]) stats_event("way_7_hit");
				else if (miss && counter_miss[6]) stats_event("way_7_evicted");
				else if (hit && counter_hit[7]) stats_event("way_8_hit");
				else if (miss && counter_miss[7]) stats_event("way_8_evicted");
				
			end

		end
	`endif
endmodule