module set_dueling #(
    parameter ASSOCIATIVITY,
	parameter SET_SIZE,
    parameter INDEX_WIDTH,
	parameter DEPTH
	) (
	input clk,   // Clock
	input rst_n,   // Synchronous reset active low
	input valid,
	input logic [`ADDR_WIDTH - 1 : 0] addr,
	input logic halt,
	input logic hit, 
	input logic miss,  
	input logic [INDEX_WIDTH - 1 : 0] i_index, 
    input logic [SET_SIZE - 1 : 0] hit_way, 
	
	output logic [SET_SIZE - 1 : 0] evict_way,
	output logic policy_1, 
	output logic policy_2, 
	output logic follower

);
	localparam M = 2; 
	localparam INIT_VAL = 2 ** M - 1; 

	localparam K_LEN = INDEX_WIDTH / 2; 
	localparam OFFSET_LEN = INDEX_WIDTH - K_LEN; 
	localparam PSEL_MAX = 2 ** INDEX_WIDTH - 1; 
	localparam PSEL_INIT = 2 ** (INDEX_WIDTH - 1) - 1; 

	logic [M - 1 : 0] main_table [DEPTH] [ASSOCIATIVITY]; 
	logic [M - 1 : 0] initial_state [DEPTH] [ASSOCIATIVITY]; 

	logic [INDEX_WIDTH - 1 : 0] PSEL; 

	logic [SET_SIZE - 1 : 0] eviction_policy_1; 
	logic [SET_SIZE - 1 : 0] eviction_policy_2; 

	logic [K_LEN - 1 : 0] CONSTITUENCY; 
	logic [OFFSET_LEN - 1 : 0] OFFSET; 


	logic [M - 1 : 0] updated_table_entry_p1 [ASSOCIATIVITY]; 
	logic [M - 1 : 0] updated_table_entry_p2 [ASSOCIATIVITY]; 

	logic [M - 1 : 0] RRPV; 


	always_comb
	begin : determine_the_identity
		RRPV = 2'b10; 
		CONSTITUENCY = 0; 
		OFFSET = 0; 
		
		policy_1 = 1'b0; 
		policy_2 = 1'b0; 
		follower = 1'b0; 

		if (valid) 
		begin
			CONSTITUENCY = i_index[INDEX_WIDTH - 1 : OFFSET_LEN]; 
			OFFSET = i_index[OFFSET_LEN - 1 : 0]; 

			if (CONSTITUENCY == OFFSET)
				policy_1 = 1'b1; 
			else if (CONSTITUENCY == ~OFFSET) 
				policy_2 = 1'b1; 
			else 
			begin
				follower = 1'b1; 
				if (PSEL[INDEX_WIDTH - 1]) policy_2 = 1'b1; 
				else policy_1 = 1'b1; 
			end
		end
	end

	DRRIP #(
		.ASSOCIATIVITY, 
		.SET_SIZE, 
		.INDEX_WIDTH, 
		.DEPTH, 
		.M,
		.SEL(1'b0)
	) SRRIP (
		.clk, 
		.rst_n, 
		.valid, 
		.hit, 
		.miss, 
		.halt,
		.hit_way, 
		.update(policy_1), 
		.main_table_entry(main_table[i_index]),
		.RRPV,

		.evict_way(eviction_policy_1),
		.updated_table_entry(updated_table_entry_p1)
	); 

	// always_comb 
	// begin
	// 	policy_1 = 1'b1; 
	// 	policy_2 = 1'b0; 
	// 	follower = 1'b0; 
	// 	evict_way = eviction_policy_1; 
	// end


	DRRIP #(
		.ASSOCIATIVITY, 
		.SET_SIZE, 
		.INDEX_WIDTH, 
		.DEPTH, 
		.M,
		.SEL(1'b1)
	) BRRIP (
		.clk, 
		.rst_n, 
		.valid, 
		.hit, 
		.miss, 
		.halt,
		.hit_way, 
		.update(policy_2), 
		.main_table_entry(main_table[i_index]),
		.RRPV,

		.evict_way(eviction_policy_2),
		.updated_table_entry(updated_table_entry_p2)
	); 

	// SHiP #(
	// .ASSOCIATIVITY, 
	// .SET_SIZE, 
	// .INDEX_WIDTH, 
	// .DEPTH, 
	// .M
	// ) hit_predictor (
	// .clk, 
	// .rst_n, 
	// .valid, 
	// .addr, 
	// .hit, 
	// .miss, 
	// .i_index,
	// .halt,
	// .hit_way, 
	// .evict_way, 

	// .RRPV
	// ); 

	always_comb 
	begin
		for (int i = 0; i < DEPTH; i++)
			initial_state[i] = '{default: INIT_VAL};
	end

	// always_ff @( posedge clk ) begin 
	// 	if (!rst_n)
	// 		main_table <= initial_state; 
	// 	else 
	// 		main_table[i_index] <= updated_table_entry; 
	// end

	always_comb
	begin : choose_eviction
		evict_way = 0; 

		if (valid)
		begin
			if (policy_1) evict_way = eviction_policy_1; 
			else evict_way = eviction_policy_2; 
		end
	end

	always_ff @(posedge clk) 
	begin
		if (!rst_n)
		begin
			PSEL <= PSEL_INIT; 
			main_table <= initial_state; 
		end
		else 
		begin
			if (valid)
			begin
				if (miss && !halt)
				begin
					if (!follower)
					begin
						if (policy_1 && PSEL > 0) PSEL <= PSEL - 1'b1;
						else if (PSEL < PSEL_MAX) PSEL <= PSEL + 1'b1; 
					end
				end
			end

			if (policy_1) main_table[i_index] <= updated_table_entry_p1; 
			else if (policy_2) main_table[i_index] <= updated_table_entry_p2; 
		end
	end

endmodule