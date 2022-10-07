module priority_encoder #(
    parameter m, // define the number of inputs
    parameter n // define the number of outputs
) (
    input logic [m - 1 : 0] x,
    input logic bottom_up, 

    output valid_in, // indicates the data input x is valid.
    output logic [n - 1 : 0] y
); 
    logic done; 
    // the body of the m-to-n priority encoder
    assign valid_in = |x;

    always_comb 
    begin
        y = '0; 
        if (bottom_up)
        begin
            for (int i = m - 1; i >= 0; i--)
            begin
                done = 1'b0; 
                if (x[i] != 0) done = 1'b1; 
                if (done == 1'b1) y = i[n - 1 : 0];
            end
        end
        else 
        begin
            for (int i = 0; i < m; i++)
            begin
                done = 1'b0; 
                if (x[i] != 0) done = 1'b1; 
                if (done == 1'b1) y = i[n - 1 : 0];
            end
        end
    end





endmodule

//credits 
//Digital System Designs and Practices Using Verilog HDL and FPGAs @ 2008, John Wiley