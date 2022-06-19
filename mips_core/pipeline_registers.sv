/*
 * pipeline_registers.sv
 * Author: Zinsser Zhang
 * Last Revision: 03/13/2022
 *
 * These are the pipeline registers between each two adjacent stages. All
 * pipeline registers are pure registers except for pr_e2m. pr_e2m needs to pass
 * through and select for addr_next signal. The reason is that we are using
 * synchronous SRAM to implement asynchronous d_cache.
 *
 * See wiki page "Synchronous Caches" for details.
 */
`include "mips_core.svh"

module pr_f2d (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	hazard_control_ifc.in i_hc,

	// Pipelined interfaces
	pc_ifc.in  i_pc,
	pc_ifc.out o_pc,

	cache_output_ifc.in  i_inst,
	cache_output_ifc.out o_inst
);

	always_ff @(posedge clk)
	begin
		if(!rst_n || i_hc.flush)
		begin
			o_pc.pc <= '0;
			o_inst.valid <= 1'b0;
			o_inst.data <= '0;
		end
		else
		begin
			if (!i_hc.stall)
			begin
				o_pc.pc <= i_pc.pc;
				o_inst.valid <= i_inst.valid;
				o_inst.data <= i_inst.data;
			end
		end
	end
endmodule

module pr_d2i (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	hazard_control_ifc.in i_hc,

	issue_input_ifc.in i_decode_pass_through, 
	issue_input_ifc.out o_decode_pass_through
); 

	always_ff @(posedge clk)
	begin
		if (!rst_n || i_hc.flush)
		begin
			o_decode_pass_through.valid <= '{default: 0}; 
			o_decode_pass_through.phys_rs <= '{default: 0}; 
			o_decode_pass_through.phys_rs_valid <= '{default: 0}; 
			o_decode_pass_through.phys_rt <= '{default: 0}; 
			o_decode_pass_through.phys_rt_valid <= '{default: 0}; 
			o_decode_pass_through.alu_ctl <= '{default: 0}; 
			o_decode_pass_through.uses_rs <= '{default: 0};  
			o_decode_pass_through.uses_rt <= '{default: 0}; 
			o_decode_pass_through.uses_immediate <= '{default: 0}; 
			o_decode_pass_through.immediate <= '{default: 0}; 
			o_decode_pass_through.is_branch <= '{default: 0}; 
			o_decode_pass_through.prediction <= '{default: 0}; 
			o_decode_pass_through.recovery_target <= '{default: 0};  
			o_decode_pass_through.is_mem_access <='{default: 0}; 
			o_decode_pass_through.mem_action <= '{default: 0}; 
			o_decode_pass_through.active_list_id <= '{default: 0}; 
		end
		else 
		begin
			if (!i_hc.stall)
			begin
				o_decode_pass_through.valid <= i_decode_pass_through.valid; 
				o_decode_pass_through.phys_rs <= i_decode_pass_through.phys_rs; 
				o_decode_pass_through.phys_rs_valid <= i_decode_pass_through.phys_rs_valid;
				o_decode_pass_through.phys_rt <= i_decode_pass_through.phys_rt;
				o_decode_pass_through.phys_rt_valid <= i_decode_pass_through.phys_rt_valid; 
				o_decode_pass_through.alu_ctl <= i_decode_pass_through.alu_ctl; 
				o_decode_pass_through.uses_rs <= i_decode_pass_through.uses_rs; 
				o_decode_pass_through.uses_rt <= i_decode_pass_through.uses_rt;
				o_decode_pass_through.uses_immediate <= i_decode_pass_through.uses_immediate;
				o_decode_pass_through.immediate <= i_decode_pass_through.immediate; 
				o_decode_pass_through.is_branch <= i_decode_pass_through.is_branch; 
				o_decode_pass_through.prediction <= i_decode_pass_through.prediction; 
				o_decode_pass_through.recovery_target <= i_decode_pass_through.recovery_target; 
				o_decode_pass_through.is_mem_access <= i_decode_pass_through.is_mem_access; 
				o_decode_pass_through.mem_action <= i_decode_pass_through.mem_action; 
				o_decode_pass_through.active_list_id <= i_decode_pass_through.active_list_id;
			end
		end
	end
endmodule


module pr_e2m (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low
	input invalidate_d_cache_output, 

	hazard_signals_ifc.in hazard_signal_in, 

	d_cache_input_ifc.in  i_d_cache_input,
	d_cache_controls_ifc.in  i_d_cache_controls,

	d_cache_input_ifc.out o_d_cache_input,
	d_cache_controls_ifc.out o_d_cache_controls
);
	// Does not register addr_next. See d_cache for details.
	always_comb
	begin
		if (hazard_signal_in.dc_miss)
			o_d_cache_input.addr_next = o_d_cache_input.addr;
		else
			o_d_cache_input.addr_next = i_d_cache_input.addr_next;
	end

	always_ff @(posedge clk)
	begin
		if(~rst_n)
		begin

			o_d_cache_input.valid <= 1'b0;
			o_d_cache_input.mem_action <= READ;
			o_d_cache_input.addr <= '0;
			o_d_cache_input.data <= '0;

			o_d_cache_controls.valid <= 1'b0; 
			o_d_cache_controls.mem_action <= READ; 
			o_d_cache_controls.bypass_possible <= '0; 
			o_d_cache_controls.bypass_index <= '0; 
			o_d_cache_controls.NOP <= 1'b1; 
			o_d_cache_controls.dispatch_index <= '0; 
		end
		else
		begin
			if (!hazard_signal_in.dc_miss)
			begin
				o_d_cache_input.valid <= i_d_cache_input.valid;
				o_d_cache_input.mem_action <= i_d_cache_input.mem_action;
				o_d_cache_input.addr <= i_d_cache_input.addr;
				o_d_cache_input.data <= i_d_cache_input.data;

				o_d_cache_controls.valid <= i_d_cache_controls.valid; 
				o_d_cache_controls.mem_action <= i_d_cache_controls.mem_action; 
				o_d_cache_controls.bypass_possible <= i_d_cache_controls.bypass_possible;
				o_d_cache_controls.bypass_index <= i_d_cache_controls.bypass_index; 
				o_d_cache_controls.NOP <= i_d_cache_controls.NOP; 
				o_d_cache_controls.dispatch_index <= i_d_cache_controls.dispatch_index; 
			end

			if (invalidate_d_cache_output)
				o_d_cache_controls.NOP <= 1'b1; 
		end
	end
endmodule
	


