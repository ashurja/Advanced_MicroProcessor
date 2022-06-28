//SEL 0 SRRIP 
//SEL 1 BRRIP

module DRRIP #(
	parameter ASSOCIATIVITY, 
	parameter SET_SIZE, 
	parameter INDEX_WIDTH, 
	parameter DEPTH, 
	parameter M,
	parameter SEL
) (
	input clk, 
	input rst_n, 
	input valid, 
	
	input logic hit, 
	input logic miss, 
	input logic halt, 

    input logic [SET_SIZE - 1 : 0] hit_way, 

	input logic update,
	input logic [M - 1 : 0] main_table_entry [ASSOCIATIVITY], 

	input logic [M - 1 : 0] RRPV,

	output logic [SET_SIZE - 1 : 0] evict_way,
	output logic [M - 1 : 0] updated_table_entry [ASSOCIATIVITY]
); 

	localparam BRRIP_COUNTER_LEN = 5; 

	localparam DISTANT = 2 ** M - 1; 
	localparam LONG = 2 ** M - 2; 
	localparam SHORT = 1; 
	localparam IMMEDIATE = 0; 

	logic [ASSOCIATIVITY - 1 : 0] evict_cmp; 
	logic [ASSOCIATIVITY - 1 : 0] alt_evict_cmp; 
	logic [ASSOCIATIVITY - 1 : 0] last_evict_cmp; 

	logic evict_valid, alt_valid, last_valid; 

	logic [SET_SIZE - 1 : 0] evict_find; 
	logic [SET_SIZE - 1 : 0] alt_evict_find; 
	logic [SET_SIZE - 1 : 0] last_evict_find; 

	logic curr_aged_state; 
	logic next_aged_state; 

	logic [SET_SIZE - 1 : 0] curr_evict_way;  
	logic [SET_SIZE - 1 : 0] next_evict_way;  

	logic [BRRIP_COUNTER_LEN - 1 : 0] curr_brrip_counter; 
	logic [BRRIP_COUNTER_LEN - 1 : 0] next_brrip_counter; 

	always_comb
	begin
		evict_cmp = 0; 
		alt_evict_cmp = 0; 
		last_evict_cmp = 0; 

		if (update && miss)
		begin
			for (int i = 0; i < ASSOCIATIVITY; i++) 
			begin
				evict_cmp[i] = (main_table_entry[i] == DISTANT); 
				alt_evict_cmp[i] = (main_table_entry[i] == LONG);
				last_evict_cmp[i] = (main_table_entry[i] == SHORT); 
			end
		end
	end

	priority_encoder# (
		.m(ASSOCIATIVITY),
		.n(SET_SIZE)
	) evict_way_retriever (
		.x(evict_cmp),
		.bottom_up(1'b1),
		.valid_in(evict_valid),
		.y(evict_find)
	); 

	priority_encoder# (
		.m(ASSOCIATIVITY),
		.n(SET_SIZE)
	) alt_evict_way_retriever (
		.x(alt_evict_cmp),
		.bottom_up(1'b1),
		.valid_in(alt_valid),
		.y(alt_evict_find)
	); 

	priority_encoder# (
		.m(ASSOCIATIVITY),
		.n(SET_SIZE)
	) last_evict_way_retriever (
		.x(last_evict_cmp),
		.bottom_up(1'b1),
		.valid_in(last_valid),
		.y(last_evict_find)
	); 

	always_comb
	begin
		next_evict_way = curr_evict_way; 
	
		if (update)
		begin
			if (miss & !halt) 
			begin
				if (evict_valid) 
				begin
					next_evict_way = evict_find; 
				end
				else if (alt_valid) 
				begin
					next_evict_way = alt_evict_find; 
				end
				else if(last_valid) 
				begin
					next_evict_way = last_evict_find; 
				end
				else 
				begin
					next_evict_way = 0; 
				end
			end
		end

		evict_way = next_evict_way; 
	end

	always_comb
	begin
		updated_table_entry = main_table_entry; 

		if (update)
		begin
			if (hit && !halt) 
			begin
				updated_table_entry[hit_way] = IMMEDIATE; 
			end
			else if (miss)
			begin
				if (!evict_valid && !curr_aged_state) 
				begin
					for (int i = 0; i < ASSOCIATIVITY; i++) 
						if (main_table_entry[i] < DISTANT) 
							updated_table_entry[i] = main_table_entry[i] + 1; 
				end
				else if (halt)
				begin
					if (SEL) 
					begin
						updated_table_entry[curr_evict_way] = (curr_brrip_counter == 0) ? LONG : DISTANT; 
					end
					else updated_table_entry[curr_evict_way] = RRPV; 
				end
			end
		end
	end

	always_comb
	begin
		next_brrip_counter = curr_brrip_counter; 
		next_aged_state = curr_aged_state; 

		if (update && miss)
		begin
			if (!halt)
			begin
				next_brrip_counter = curr_brrip_counter + 1'b1; 
				next_aged_state = 1'b0; 
			end
			else if (evict_valid)
			begin
				next_aged_state = 1'b1; 
			end
		end
	end

	always_ff @(posedge clk) 
	begin
		if (!rst_n) 
		begin
			curr_aged_state <= 1'b0; 
			curr_evict_way <= 0; 
		end

		else 
		begin
			curr_brrip_counter <= next_brrip_counter; 
			curr_evict_way <= next_evict_way; 
			curr_aged_state <= next_aged_state;
		end
	end

endmodule