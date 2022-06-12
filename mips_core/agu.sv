`include "mips_core.svh"

interface agu_input_ifc ();
	logic valid;
	logic signed [`DATA_WIDTH - 1 : 0] op1;
	logic signed [`DATA_WIDTH - 1 : 0] op2;

	modport in  (input valid, op1, op2);
	modport out (output valid, op1, op2);
endinterface

interface agu_output_ifc ();
	logic valid;
	logic [`DATA_WIDTH - 1 : 0] result;

	modport in  (input valid, result);
	modport out (output valid, result);
endinterface

module agu (
	agu_input_ifc.in in,
	agu_output_ifc.out out
);

	always_comb
	begin
		out.valid = 1'b0;
		out.result = '0;
		if (in.valid)
		begin
			out.valid = 1'b1;
			out.result = in.op1 + in.op2;
		end
	end
endmodule
