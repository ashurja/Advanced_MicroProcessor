/*
 * hazard_controller.sv
 * Author: Zinsser Zhang
 * Last Revision: 03/13/2022
 *
 * hazard_controller collects feedbacks from each stage and detect whether there
 * are hazards in the pipeline. If so, it generate control signals to stall or
 * flush each stage. It also contains a branch_controller, which talks to
 * a branch predictor to make a prediction when a branch instruction is decoded.
 *
 * It also contains simulation only logic to report hazard conditions to C++
 * code for execution statistics collection.
 *
 * See wiki page "Hazards" for details.
 * See wiki page "Branch and Jump" for details of branch and jump instructions.
 */
`include "mips_core.svh"

`ifdef SIMULATION
import "DPI-C" function void stats_event (input string e);
`endif


module hazard_controller (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low


	input logic mem_done,
	input logic decode_hazard,
	input logic issue_queue_full,
	input logic front_pipeline_halt, 

	cache_output_ifc.in if_i_cache_output,
	pc_ifc.in dec_pc,
	branch_decoded_ifc.hazard dec_branch_decoded,
	branch_result_ifc.in ex_branch_result,

	rename_ifc.in next_rename_state, 
	// Hazard control output
	hazard_control_ifc.out f2f_hc,
	hazard_control_ifc.out f2d_hc,
	hazard_control_ifc.out d2i_hc,

	hazard_signals_ifc.out hazard_signal_out, 
	// Load pc output
	load_pc_ifc.out load_pc
);

	branch_controller BRANCH_CONTROLLER (
		.clk, .rst_n,
		.dec_pc,
		.dec_branch_decoded,
		.ex_branch_result
	);

	//Profiling
	logic is_branch; 

	// We have total potential hazards
	logic ic_miss;			// I cache miss
	logic ds_miss;			// Delay slot miss
	logic dec_overload;		// Branch predict taken or Jump
	logic ex_overload;		// Branch prediction wrong
	logic dc_miss;			// D cache miss

	// Determine if we have these hazards
	always_comb
	begin : profiling
		is_branch = ex_branch_result.valid; 
	end

	always_comb
	begin
		ic_miss = ~if_i_cache_output.valid;
		dec_overload = dec_branch_decoded.valid
			& (dec_branch_decoded.is_jump
				| (dec_branch_decoded.prediction == TAKEN));
		ex_overload = ex_branch_result.valid
			& (ex_branch_result.prediction != ex_branch_result.outcome);
		dc_miss = ~mem_done;
	end

	// Control signals
	logic if_stall, if_flush;
	logic dec_stall, dec_flush;
	logic issue_stall; 
	// wb doesn't need to be stalled or flushed
	// i.e. any data goes to wb is finalized and waiting to be commited

	/*
	 * Now let's go over the solution of all hazards
	 * ic_miss:
	 *     if_stall, if_flush
	 * ds_miss:
	 *     dec_stall, dec_flush (if_stall and if_flush handled by ic_miss)
	 * dec_overload:
	 *     load_pc
	 * ex_overload:
	 *     load_pc, ~if_stall, if_flush
	 * lw_hazard:
	 *     dec_stall, dec_flush
	 * dc_miss:
	 *     mem_stall, mem_flush
	 * decode_hazard
	 	   if_stall, dec_stall, dec_flush
	   queue_full
		   issue_stall, dec_stall, if_stall
		misprediction
			if_flush, dec_flush
	   dc_miss
	   		dc_stall, issue_mem_flush
	   	   
	 * The only conflict here is between ic_miss and ex_overload.
	 * ex_overload should have higher priority than ic_miss. Because i cache
	 * does not register missed request, it's totally fine to directly overload
	 * the pc value.
	 *
	 * In addition to above hazards, each stage should also stall if its
	 * downstream stage stalls (e.g., when mem stalls, if & dec & ex should all
	 * stall). This has the highest priority.
	 */


	always_comb
	begin : handle_if
		if_stall = 1'b0;
		if_flush = 1'b0;

		if (ic_miss)
		begin
			if_stall = 1'b1;
			if_flush = 1'b1;
		end

		if (dec_stall)
		begin
			if_stall = 1'b1;
			if_flush = 1'b0; 
		end


		if (ex_overload)
		begin
			if_stall = 1'b0;
			if_flush = 1'b1;
		end


	end

	always_comb
	begin : handle_dec
		dec_stall = 1'b0;
		dec_flush = 1'b0;

		if (next_rename_state.branch_decoded_hazard)
			dec_flush = 1'b1; 

		if (decode_hazard)
		begin
			dec_stall = 1'b1;
			dec_flush = 1'b1;
		end

		if (issue_stall)
		begin
			dec_stall = 1'b1; 
			dec_flush = 1'b0; 
		end

		if (ex_overload)
		begin
			dec_stall = 1'b0; 
			dec_flush = 1'b1; 
		end

	end

	always_comb
	begin : handle_issue
		issue_stall = 1'b0; 

		if (issue_queue_full)
			issue_stall = 1'b1; 

		if (ex_overload)
			issue_stall = 1'b0; 
	

	end


	// Now distribute the control signals to each pipeline registers
	always_comb
	begin
		f2f_hc.flush = 1'b0;
		f2f_hc.stall = if_stall;
		f2d_hc.flush = if_flush;
		f2d_hc.stall = dec_stall;
		d2i_hc.flush = dec_flush;
		d2i_hc.stall = issue_stall;
	end


	// Derive the load_pc
	always_comb
	begin
		load_pc.we = dec_overload | ex_overload;
		if (dec_overload)
			load_pc.new_pc = dec_branch_decoded.target;
		else
			load_pc.new_pc = ex_branch_result.recovery_target;
	end



	always_comb
	begin
		hazard_signal_out.ic_miss = ic_miss; 
		hazard_signal_out.dc_miss = dc_miss; 
		hazard_signal_out.branch_miss = ex_overload; 
		hazard_signal_out.branch_id = ex_branch_result.branch_id; 
		hazard_signal_out.color_bit = ex_branch_result.color_bit; 
	end

/************************************  SIMULATION AND PROFILING *************************************/
/***************************************************************************************************/
	logic dc_miss_checkpoint; 
	logic mem_halt; 

	logic ic_miss_checkpoint; 
	logic inst_halt; 

	always_comb
	begin
		mem_halt = 1'b0; 
		inst_halt = 1'b0; 
		if (dc_miss_checkpoint == dc_miss) mem_halt = 1'b1; 
		if (ic_miss_checkpoint == ic_miss) inst_halt = 1'b1; 
	end

	always_ff @(posedge clk)
	begin
		if (!rst_n)
		begin
			dc_miss_checkpoint <= 1'b0; 
			ic_miss_checkpoint <= 1'b0; 
		end
		else 
		begin
			dc_miss_checkpoint <= ~mem_done; 
			ic_miss_checkpoint <= ~if_i_cache_output.valid; 
		end
		
	end

`ifdef SIMULATION
	always_ff @(posedge clk)
	begin
		if (ic_miss && !inst_halt) stats_event("ic_miss");
		if (dec_overload && mem_done) stats_event("dec_overload");
		if (ex_overload) stats_event("ex_overload");
		if (dc_miss && !mem_halt) stats_event("dc_miss");
		if (ex_branch_result.valid) stats_event("is_branch"); 
		if (issue_queue_full && !front_pipeline_halt) stats_event("issue_queue_full"); 
	end
`endif

endmodule
