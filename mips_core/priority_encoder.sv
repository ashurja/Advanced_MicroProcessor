module priority_encoder #(
    parameter m, // define the number of inputs
    parameter n // define the number of outputs
) (
    input logic [m - 1 : 0] x,
    input logic bottom_up, 

    output valid_in, // indicates the data input x is valid.
    output logic [n - 1 : 0] y
); 
    integer i;
    // the body of the m-to-n priority encoder
    assign valid_in = |x;

    always_comb 
    begin
        if (!bottom_up)
        begin
            i = m - 1;
            while(x[i] == 0 && i > 0 ) i = i - 1;
            y = i[n - 1 : 0];
        end
        else 
        begin
            i = 0;
            while(x[i] == 0 && i < m - 1 ) i = i + 1;
            y = i[n - 1 : 0];
        end
    end
endmodule

//credits 
//Digital System Designs and Practices Using Verilog HDL and FPGAs @ 2008, John Wiley