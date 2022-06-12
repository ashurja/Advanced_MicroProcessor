module hashing #(
    parameter LEN_BITS_HASHING,
    parameter LEN_BITS_OUTPUT,
    parameter SOURCE_LEN
) (
    input logic [SOURCE_LEN - 1 : 0] source,
    output logic [LEN_BITS_OUTPUT - 1 : 0] hash
);
    localparam NUM_HASH_SETS = LEN_BITS_HASHING / LEN_BITS_OUTPUT + 1; 
    localparam INDEX_NUM_HASH_SETS = (NUM_HASH_SETS == 1) ? 1 : $clog2(NUM_HASH_SETS);

    logic [NUM_HASH_SETS - 1 : 0] hash_sets [LEN_BITS_OUTPUT];

    logic [$clog2(LEN_BITS_OUTPUT) - 1 : 0] h_index; 
	logic [INDEX_NUM_HASH_SETS - 1 : 0] h_bit; 

    always_comb begin : compute_hash 
        for (int i = 0; i < LEN_BITS_HASHING; i++)
        begin
            h_index = i % LEN_BITS_OUTPUT; 
            h_bit = i / LEN_BITS_OUTPUT; 
            hash_sets[h_index][h_bit] = source[i % SOURCE_LEN]; 
        end
        
        for (int i = 0; i < LEN_BITS_OUTPUT; i++)
        begin
            hash[i] = ^hash_sets[i]; 
        end
    end

endmodule