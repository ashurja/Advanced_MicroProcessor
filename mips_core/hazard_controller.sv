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


module hazard_controller(
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low


	input logic mem_done,
	input logic decode_hazard,
	input logic issue_hazard,
	input logic front_pipeline_halt, 

	branch_controls_ifc.in curr_branch_controls,
	branch_controls_ifc.in misprediction_branch_controls,
	cache_output_ifc.in if_i_cache_output,
	pc_ifc.in dec_pc,
	branch_decoded_ifc.hazard dec_branch_decoded,
	branch_result_ifc.in ex_branch_result,

	rename_ifc.in next_rename_state, 
	// Hazard control output
	hazard_control_ifc.out f2f_hc,
	hazard_control_ifc.out f2d_hc,
	hazard_control_ifc.out d2i_hc,

	branch_controls_ifc.out next_branch_controls, 
	hazard_signals_ifc.out hazard_signal_out, 
	// Load pc output
	load_pc_ifc.out load_pc
);

	branch_controller BRANCH_CONTROLLER(
		.clk, .rst_n,
		.curr_branch_controls,
		.misprediction_branch_controls, 
		.dec_pc,
		.dec_branch_decoded,
		.ex_branch_result
	);
	localparam L1 = 4;
	localparam alpha = 2;
	localparam int TAGE_G_SEQ [`TAGE_TABLE_NUM - 1] = '{L1 * (alpha** 0), L1 * (alpha** 1) + 1, L1 * (alpha** 2), L1 * (alpha** 3) + 1, L1 * (alpha** 4), L1 * (alpha** 5) + 1, L1 * (alpha** 6)}; 
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

	always_comb
	begin
		if (!rst_n) begin 
			next_branch_controls.GHR = '0; 

            for (int i = 0; i < `TAGE_TABLE_NUM - 1; i++) begin 
                next_branch_controls.CSR_IDX[i] = {($clog2(`TAGE_TABLE_LEN)){1'b1}}; 
                next_branch_controls.CSR_TAG[i] = {(`TAGE_TAG_WIDTH){1'b1}};  
                next_branch_controls.CSR_TAG_2[i] = {(`TAGE_TAG_WIDTH - 1){1'b1}}; 

				next_branch_controls.CSR_IDX_FEED[i] = {($clog2(`TAGE_TABLE_LEN)){1'b1}}; 
                next_branch_controls.CSR_TAG_FEED[i] = {(`TAGE_TAG_WIDTH){1'b1}};  
                next_branch_controls.CSR_TAG_2_FEED[i] = {(`TAGE_TAG_WIDTH - 1){1'b1}}; 
            end
		end
		else 
		begin
			next_branch_controls.GHR = curr_branch_controls.GHR; 

			next_branch_controls.CSR_IDX = curr_branch_controls.CSR_IDX; 
			next_branch_controls.CSR_TAG = curr_branch_controls.CSR_TAG; 
			next_branch_controls.CSR_TAG_2 = curr_branch_controls.CSR_TAG_2; 

			next_branch_controls.CSR_IDX_FEED = curr_branch_controls.CSR_IDX_FEED; 
			next_branch_controls.CSR_TAG_FEED = curr_branch_controls.CSR_TAG_FEED; 
			next_branch_controls.CSR_TAG_2_FEED = curr_branch_controls.CSR_TAG_2_FEED; 
		end

		if (dec_branch_decoded.valid & ~dec_branch_decoded.is_jump & !decode_hazard)
		begin
			next_branch_controls.GHR = {curr_branch_controls.GHR[`GHR_LEN - 2 : 0], dec_branch_decoded.prediction}; 

			for (int i = 0; i < `TAGE_TABLE_NUM - 1; i++) begin 

				if (TAGE_G_SEQ[i] % $clog2(`TAGE_TABLE_LEN) == 0) begin 
					next_branch_controls.CSR_IDX[i] = {curr_branch_controls.CSR_IDX[i][$clog2(`TAGE_TABLE_LEN) - 2 : 0], curr_branch_controls.CSR_IDX[i][$clog2(`TAGE_TABLE_LEN) - 1] ^ dec_branch_decoded.prediction ^ curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1]};
				end
				else begin 
					next_branch_controls.CSR_IDX[i] = {curr_branch_controls.CSR_IDX[i][$clog2(`TAGE_TABLE_LEN) - 2 : 0], curr_branch_controls.CSR_IDX[i][$clog2(`TAGE_TABLE_LEN) - 1] ^ dec_branch_decoded.prediction};
					next_branch_controls.CSR_IDX[i][(TAGE_G_SEQ[i] % $clog2(`TAGE_TABLE_LEN))] = curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1] ^ curr_branch_controls.CSR_IDX[i][(TAGE_G_SEQ[i] % $clog2(`TAGE_TABLE_LEN)) - 1];
				end

				if (TAGE_G_SEQ[i] % `TAGE_TAG_WIDTH == 0) begin 
					next_branch_controls.CSR_TAG[i] = {curr_branch_controls.CSR_TAG[i][`TAGE_TAG_WIDTH - 2 : 0], curr_branch_controls.CSR_TAG[i][`TAGE_TAG_WIDTH - 1] ^ dec_branch_decoded.prediction ^ curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1]};
				end
				else begin 
					next_branch_controls.CSR_TAG[i] = {curr_branch_controls.CSR_TAG[i][`TAGE_TAG_WIDTH - 2 : 0], curr_branch_controls.CSR_TAG[i][`TAGE_TAG_WIDTH - 1] ^ dec_branch_decoded.prediction};
					next_branch_controls.CSR_TAG[i][(TAGE_G_SEQ[i] % `TAGE_TAG_WIDTH)] = curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1] ^ curr_branch_controls.CSR_TAG[i][(TAGE_G_SEQ[i] % `TAGE_TAG_WIDTH) - 1];
				end

				if (TAGE_G_SEQ[i] % (`TAGE_TAG_WIDTH - 1) == 0) begin 
					next_branch_controls.CSR_TAG_2[i] = {curr_branch_controls.CSR_TAG_2[i][(`TAGE_TAG_WIDTH - 1) - 2 : 0], curr_branch_controls.CSR_TAG_2[i][(`TAGE_TAG_WIDTH - 1) - 1] ^ dec_branch_decoded.prediction ^ curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1]};
				end
				else begin 
					next_branch_controls.CSR_TAG_2[i] = {curr_branch_controls.CSR_TAG_2[i][(`TAGE_TAG_WIDTH - 1) - 2 : 0], curr_branch_controls.CSR_TAG_2[i][(`TAGE_TAG_WIDTH - 1) - 1] ^ dec_branch_decoded.prediction};	
					next_branch_controls.CSR_TAG_2[i][(TAGE_G_SEQ[i] % (`TAGE_TAG_WIDTH - 1))] = curr_branch_controls.GHR[TAGE_G_SEQ[i] - 1] ^ curr_branch_controls.CSR_TAG_2[i][(TAGE_G_SEQ[i] % (`TAGE_TAG_WIDTH - 1)) - 1];
				end
			end
		end
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

		if (issue_hazard)
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
		if (ex_overload)
			load_pc.new_pc = ex_branch_result.recovery_target;
		else
			load_pc.new_pc = dec_branch_decoded.target;
			
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

`ifdef SIMULATION
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

	always_ff @(posedge clk)
	begin
		if (ic_miss && !inst_halt) stats_event("ic_miss");
		if (dec_overload && mem_done) stats_event("dec_overload");
		if (ex_overload) stats_event("ex_overload");
		if (dc_miss && !mem_halt) stats_event("dc_miss");
		if (ex_branch_result.valid) stats_event("is_branch"); 
	end
`endif

endmodule
