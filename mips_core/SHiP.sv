`include "mips_core.svh"

module SHiP #(
    parameter ASSOCIATIVITY, 
    parameter SET_SIZE,
    parameter INDEX_WIDTH, 
    parameter DEPTH, 
    parameter M 
) (
   	input clk,   // Clock
	input rst_n,   // Synchronous reset active low
	input valid,
	input logic [`ADDR_WIDTH - 1 : 0] pc,
	input logic halt,
	input logic hit, 
	input logic miss,  
	input logic [INDEX_WIDTH - 1 : 0] i_index, 
    input logic [SET_SIZE - 1 : 0] hit_way, 
    input logic [SET_SIZE - 1 : 0] evict_way, 

    output logic [M - 1 : 0] RRPV
);
    localparam TABLE_LEN = 8096; 
    localparam COUNTER_LEN = 2; 
    localparam COUNTER_MAX = COUNTER_LEN ** 2 - 1; 
    localparam SIG_LEN = $clog2(TABLE_LEN); 

	localparam DISTANT = 2 ** M - 1; 
	localparam LONG = 2 ** M - 2; 
	localparam SHORT = 1; 
	localparam IMMEDIATE = 0; 

    logic [COUNTER_LEN - 1 : 0] SHCT [TABLE_LEN]; 
    logic outcome_bit [ASSOCIATIVITY] [DEPTH]; 
    logic [SIG_LEN - 1 : 0] signature [ASSOCIATIVITY] [DEPTH]; 

    logic [SIG_LEN - 1 : 0] curr_sig; 
    logic [SIG_LEN - 1 : 0] evict_sig; 

    always_comb 
    begin
        curr_sig = 0;
        evict_sig = 0; 

        if (valid) curr_sig = pc[`ADDR_WIDTH - 1 : `ADDR_WIDTH - SIG_LEN]; 
        if (valid) evict_sig = signature[evict_way][i_index]; 
    end

    always_comb
    begin
        if (SHCT[curr_sig] == 0)
            RRPV = DISTANT; 
        else 
            RRPV = LONG; 
    end

    always_ff @(posedge clk)
    begin
        if (!rst_n)
        begin
            SHCT <= '{default: 0};
            for (int i = 0; i < ASSOCIATIVITY; i++)
            begin
                outcome_bit[i] <= '{default: 1'b0};
                signature[i] <= '{default: 0};
            end
        end
        else if (valid)
        begin
            if (hit & !halt)
            begin
                outcome_bit[hit_way][i_index] <= 1'b1; 
                if (SHCT[curr_sig] < COUNTER_MAX) SHCT[curr_sig] <= SHCT[curr_sig] + 1'b1; 
            end
            else if (miss & !halt)
            begin
                if (outcome_bit[evict_way][i_index] == 1'b0)
                begin
                    if (SHCT[evict_sig] > 0) SHCT[evict_sig] <= SHCT[evict_sig] - 1'b1;
                end
                outcome_bit[evict_way][i_index] <= 1'b0; 
                signature[evict_way][i_index] <= curr_sig; 
            end
        end
    end


endmodule