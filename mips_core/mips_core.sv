/* mips_core.sv
* Author: Pravin P. Prabhu, Dean Tullsen, and Zinsser Zhang
* Last Revision: 03/13/2022
* Abstract:
*   The core module for the MIPS32 processor. This is a classic 5-stage
* MIPS pipeline architecture which is intended to follow heavily from the model
* presented in Hennessy and Patterson's Computer Organization and Design.
* All addresses used in this scope are byte addresses (26-bit)
*/
`include "mips_core.svh"

`ifdef SIMULATION
import "DPI-C" function void pc_event (input int pc);
import "DPI-C" function void wb_event (input int addr, input int data);
import "DPI-C" function void ls_event (input int op, input int addr, input int data);
`endif

module mips_core (
	// General signals
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low
	output logic done,  // Execution is done

	// AXI interfaces
	input AWREADY,
	output AWVALID,
	output [3:0] AWID,
	output [3:0] AWLEN,
	output [`ADDR_WIDTH - 1 : 0] AWADDR,

	input WREADY,
	output WVALID,
	output WLAST,
	output [3:0] WID,
	output [`DATA_WIDTH - 1 : 0] WDATA,

	output BREADY,
	input BVALID,
	input [3:0] BID,

	input ARREADY,
	output ARVALID,
	output [3:0] ARID,
	output [3:0] ARLEN,
	output [`ADDR_WIDTH - 1 : 0] ARADDR,

	output RREADY,
	input RVALID,
	input RLAST,
	input [3:0] RID,
	input [`DATA_WIDTH - 1 : 0] RDATA
);

	// Interfaces
	// |||| IF Stage
	pc_ifc if_pc_current();
	pc_ifc if_pc_next();
	cache_output_ifc if_i_cache_output();

	// ==== IF to DEC
	pc_ifc f2d_pc();
	cache_output_ifc f2d_inst();

	// Decode&Rename

	decoder_output_ifc dec_decoder_output();
	branch_decoded_ifc dec_branch_decoded();

	rename_ifc curr_rename_state();
	active_state_ifc curr_active_state(); 

	rename_ifc next_rename_state();
	active_state_ifc next_active_state(); 

	reg_file_output_ifc reg_file_out(); 

	// ISSUE/SCHEDULE
	issue_input_ifc decode_pass_through (); 
	issue_input_ifc buffered_issue_state (); 
	issue_input_ifc issue_input(); 

	scheduler_output_ifc scheduler_out(); 

	integer_issue_queue_ifc curr_int_queue(); 
	memory_issue_queue_ifc curr_mem_queue(); 
	integer_issue_queue_ifc next_int_queue(); 
	memory_issue_queue_ifc next_mem_queue(); 

	// EX 
	alu_input_ifc alu_input();
	agu_input_ifc agu_input(); 

	alu_output_ifc alu_output();
	agu_output_ifc agu_output(); 

	branch_result_ifc ex_branch_result();

	// MEM 
	d_cache_controls_ifc i_d_cache_controls(); 
	d_cache_input_ifc i_d_cache_input();

	d_cache_controls_ifc o_d_cache_controls(); 
	d_cache_input_ifc o_d_cache_input();

	cache_output_ifc d_cache_output();

	load_queue_ifc curr_load_queue(); 
	store_queue_ifc curr_store_queue(); 
	load_queue_ifc next_load_queue(); 
	store_queue_ifc next_store_queue(); 



	// COMMIT
	commit_output_ifc commit_out(); 

	inst_commit_ifc int_commit(); 
	inst_commit_ifc mem_commit(); 

	commit_state_ifc curr_commit_state(); 
	commit_state_ifc next_commit_state(); 
	// Write_back

	write_back_ifc load_write_back();
	write_back_ifc alu_write_back();


	rename_ifc misprediction_rename_state(); 
	active_state_ifc misprediction_active_state(); 
	integer_issue_queue_ifc misprediction_int_queue(); 
	memory_issue_queue_ifc misprediction_mem_queue(); 
	load_queue_ifc misprediction_load_queue(); 
	store_queue_ifc misprediction_store_queue(); 
	branch_state_ifc misprediction_branch_state(); 
	misprediction_output_ifc misprediction_out(); 
	// xxxx Hazard control

	logic mem_done;
	logic issue_hazard; 
	logic decode_hazard; 
	logic load_store_queue_full; 
	logic misprediction_recovery; 
	logic invalidate_d_cache_output; 

	logic front_pipeline_halt; 

	branch_state_ifc curr_branch_state(); 
	branch_state_ifc next_branch_state(); 

	hazard_signals_ifc hazard_signals(); 
	hazard_control_ifc f2f_hc();
	hazard_control_ifc f2d_hc();
	hazard_control_ifc d2i_hc();
	load_pc_ifc load_pc();


	//SIMULATION
	simulation_verification_ifc simulation_verification(); 


	// xxxx Memory
	axi_write_address axi_write_address();
	axi_write_data axi_write_data();
	axi_write_response axi_write_response();
	axi_read_address axi_read_address();
	axi_read_data axi_read_data();

	axi_write_address mem_write_address[1]();
	axi_write_data mem_write_data[1]();
	axi_write_response mem_write_response[1]();
	axi_read_address mem_read_address[2]();
	axi_read_data mem_read_data[2]();


	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	// |||| IF Stage
	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	fetch_unit FETCH_UNIT(
		.clk, .rst_n,

		.i_hc         (f2f_hc),
		.i_load_pc    (load_pc),

		.o_pc_current (if_pc_current),
		.o_pc_next    (if_pc_next)
	);

	i_cache I_CACHE(
		.clk, .rst_n,

		.mem_read_address(mem_read_address[0]),
		.mem_read_data   (mem_read_data[0]),

		.i_pc_current (if_pc_current),
		.i_pc_next    (if_pc_next),

		.out          (if_i_cache_output)
	);
	// If you want to change the line size and total size of instruction cache,
	// uncomment the following two lines and change the parameter.

	// defparam D_CACHE.INDEX_WIDTH = 9,
	// 	D_CACHE.BLOCK_OFFSET_WIDTH = 2;

	// ========================================================================
	// ==== IF to DEC
	// ========================================================================
	pr_f2d PR_F2D(
		.clk, .rst_n,
		.i_hc(f2d_hc),

		.i_pc   (if_pc_current),     .o_pc   (f2d_pc),
		.i_inst (if_i_cache_output), .o_inst (f2d_inst)
	);

	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	// |||| DEC Stage
	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	decoder DECODER(
		.i_pc(f2d_pc),
		.i_inst(f2d_inst),

		.out(dec_decoder_output)
	);

	reg_file REG_FILE(
		.clk,
		.rst_n,
		.load_store_queue_full,
		.issue_hazard, 

		.hazard_signal_in(hazard_signals), 

		.pc_in(f2d_pc),
		.i_decoded(dec_decoder_output),
		.i_inst(f2d_inst), 
		.i_alu_write_back(alu_write_back),
		.i_load_write_back(load_write_back),
		.curr_rename_state,
		.curr_active_state,
		.curr_branch_state,
		.i_commit_out(commit_out), 
		.curr_commit_state, 

		.next_active_state, 
		.next_rename_state,
		.out(reg_file_out), 
		.decode_hazard, 
		.front_pipeline_halt
	);


	decode_stage_glue DEC_STAGE_GLUE(
		.i_decoded          (dec_decoder_output),
		.i_reg_data         (reg_file_out),
		.curr_rename_state, 
		.next_rename_state, 
		.buffered_issue_state,

		.branch_decoded     (dec_branch_decoded),
		.o_decode_pass_through		(decode_pass_through)

	);

	pr_d2i PR_D2I (
		.clk, .rst_n, 
		.i_hc(d2i_hc), 

		.i_decode_pass_through(decode_pass_through), 
		.o_decode_pass_through(issue_input) 
	); 


	issue ISSUE (
		.clk, .rst_n,
		.front_pipeline_halt, 

		.issue_in(issue_input),
		.curr_mem_queue,
		.curr_int_queue,
		.curr_branch_state, 

		.hazard_signal_in(hazard_signals),

		.i_alu_write_back(alu_write_back), 
		.i_load_write_back(load_write_back), 

		.next_mem_queue, 
		.next_int_queue, 
		.next_branch_state, 

		.issue_hazard
	); 

	// ========================================================================
	// ==== DEC to EX
	// ========================================================================
	

	scheduler SCHEDULER (
		.hazard_signal_in(hazard_signals), 

		.curr_mem_queue, 
		.curr_int_queue, 
		.curr_rename_state, 
		.i_alu_output(alu_output), 
		.curr_active_state, 


		.o_scheduler(scheduler_out), 
		.o_alu_write_back(alu_write_back), 
		.o_alu_input(alu_input), 
		.o_agu_input(agu_input), 
		.o_branch_result(ex_branch_result), 
		.o_int_commit(int_commit) 
	);


	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	// |||| EX Stage
	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	alu ALU(
		.in(alu_input),
		.out(alu_output)
	);

	agu AGU (
		.in (agu_input),
		.out (agu_output)
	);

	load_store_queue LOAD_STORE_QUEUE (
		.rst_n, 
 
		.hazard_signal_in(hazard_signals), 
		.i_scheduler(scheduler_out),
		.i_reg_data(reg_file_out), 
		.i_agu_output(agu_output), 
		.curr_active_state,
		.curr_load_queue, 
		.curr_store_queue, 
		.curr_mem_queue, 
		.misprediction_load_queue, 
		.misprediction_store_queue,
		.i_commit_out(commit_out), 
		.curr_rename_state,
		.curr_commit_state,

		.next_load_queue, 
		.next_store_queue, 
		.o_d_cache_controls(i_d_cache_controls), 
		.o_d_cache_input(i_d_cache_input), 

		.load_store_queue_full
	); 

	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	// |||| MEM Stage
	// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
	pr_e2m PR_E2M (
		.clk, .rst_n, 

		.misprediction_out, 
		.hazard_signal_in(hazard_signals), 
		.i_d_cache_input,
		.i_d_cache_controls, 

		.o_d_cache_input,
		.o_d_cache_controls
	); 
	
	
	d_cache D_CACHE (
		.clk, .rst_n,

		.in(o_d_cache_input),
		.out(d_cache_output),

		.mem_read_address(mem_read_address[1]),
		.mem_read_data   (mem_read_data[1]),

		.mem_write_address(mem_write_address[0]),
		.mem_write_data(mem_write_data[0]),
		.mem_write_response(mem_write_response[0])
	);

	mem_stage_glue MEM_GLUE (
		.curr_load_queue, 
		.curr_store_queue, 
		.d_cache_output, 
		.o_d_cache_controls, 

		.o_load_write_back(load_write_back), 
		.o_mem_commit(mem_commit), 
		.o_done(mem_done)
	); 

	commit COMMIT (
		.clk, .rst_n, 
		.hazard_signal_in(hazard_signals), 
		.misprediction_out, 
		.i_int_commit(int_commit), 
		.i_mem_commit(mem_commit), 
		.curr_commit_state, 
		.curr_active_state, 
		.curr_rename_state, 
		.next_rename_state,
		.curr_load_queue, 
		.curr_store_queue, 
		.curr_branch_state, 
		.alu_input,

		.o_commit_out(commit_out), 
		.next_commit_state,
		.simulation_verification
	); 

	branch_misprediction BRANCH_MISPREDICTION (
		.rst_n,

		.hazard_signal_in(hazard_signals),
		.o_d_cache_controls,

		.curr_branch_state,
		.curr_rename_state, 
		.curr_active_state, 
		.curr_int_queue, 
		.curr_mem_queue, 
		.curr_load_queue, 
		.curr_store_queue, 
		.curr_commit_state, 

		.misprediction_rename_state, 
		.misprediction_active_state, 
		.misprediction_int_queue, 
		.misprediction_mem_queue, 
		.misprediction_load_queue, 
		.misprediction_store_queue, 
		.misprediction_branch_state, 
		.misprediction_out
	); 

	data_struct_update DATA_STRCUTURES_UPDATE (
		.clk, 
		.rst_n, 

		.hazard_signal_in(hazard_signals), 

		.i_d_cache_controls,
		.i_scheduler(scheduler_out),
		.i_commit_out(commit_out), 
		.i_load_write_back(load_write_back),
		.i_reg_data(reg_file_out),
		.i_decode_pass_through(decode_pass_through),
 
		.next_rename_state, 
		.next_active_state, 
		.next_commit_state, 
		.next_int_queue, 
		.next_mem_queue,
		.next_branch_state, 
		.next_load_queue, 
		.next_store_queue, 

		.misprediction_rename_state, 
		.misprediction_active_state, 
		.misprediction_int_queue, 
		.misprediction_mem_queue, 
		.misprediction_load_queue, 
		.misprediction_store_queue, 
		.misprediction_branch_state, 

		.buffered_issue_state,
		.curr_rename_state, 
		.curr_active_state, 
		.curr_commit_state, 
		.curr_int_queue, 
		.curr_mem_queue,
		.curr_branch_state, 
		.curr_load_queue, 
		.curr_store_queue 
	); 
	// If you want to change the line size and total size of data cache,
	// uncomment the following two lines and change the parameter.

	// defparam D_CACHE.INDEX_WIDTH = 9,
	// 	D_CACHE.BLOCK_OFFSET_WIDTH = 2;


	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	// xxxx Hazard Controller
	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	hazard_controller HAZARD_CONTROLLER (
		.clk, .rst_n,

		.mem_done, 
		.decode_hazard, 
		.issue_hazard, 
		.front_pipeline_halt, 

		.next_rename_state,

		.if_i_cache_output,
		.dec_pc(f2d_pc),
		.dec_branch_decoded,
		.ex_branch_result,

		.hazard_signal_out(hazard_signals), 
		.f2f_hc,
		.f2d_hc,
		.d2i_hc,
		.load_pc
	);

	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	// xxxx Memory Arbiter
	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	memory_arbiter #(.WRITE_MASTERS(1), .READ_MASTERS(2)) MEMORY_ARBITER (
		.clk, .rst_n,
		.axi_write_address,
		.axi_write_data,
		.axi_write_response,
		.axi_read_address,
		.axi_read_data,

		.mem_write_address,
		.mem_write_data,
		.mem_write_response,
		.mem_read_address,
		.mem_read_data
	);

	assign axi_write_address.AWREADY = AWREADY;
	assign AWVALID = axi_write_address.AWVALID;
	assign AWID = axi_write_address.AWID;
	assign AWLEN = axi_write_address.AWLEN;
	assign AWADDR = axi_write_address.AWADDR;

	assign axi_write_data.WREADY = WREADY;
	assign WVALID = axi_write_data.WVALID;
	assign WLAST = axi_write_data.WLAST;
	assign WID = axi_write_data.WID;
	assign WDATA = axi_write_data.WDATA;

	assign axi_write_response.BVALID = BVALID;
	assign axi_write_response.BID = BID;
	assign BREADY = axi_write_response.BREADY;

	assign axi_read_address.ARREADY = ARREADY;
	assign ARVALID = axi_read_address.ARVALID;
	assign ARID = axi_read_address.ARID;
	assign ARLEN = axi_read_address.ARLEN;
	assign ARADDR = axi_read_address.ARADDR;

	assign RREADY = axi_read_data.RREADY;
	assign axi_read_data.RVALID = RVALID;
	assign axi_read_data.RLAST = RLAST;
	assign axi_read_data.RID = RID;
	assign axi_read_data.RDATA = RDATA;

	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	// xxxx Debug and statistic collect logic (Not synthesizable)
	// xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

`ifdef SIMULATION
	always_ff @(posedge clk)
	begin
		done <= 1'b0; 
		for (int i = 0; i <= commit_out.last_valid_commit_idx; i++)
		begin
			if (commit_out.commit_valid)
			begin
				if (curr_active_state.alu_ctl[simulation_verification.active_list_id[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]] == ALUCTL_MTC0_DONE)
				begin
					done <= 1'b1;
					`ifdef SIMULATION
						$display("%m (%t) DONE test %x", $time, simulation_verification.op2[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);
					`endif
				end
				else if (curr_active_state.alu_ctl[simulation_verification.active_list_id[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]] == ALUCTL_MTC0_PASS)
				begin
					`ifdef SIMULATION
						$display("%m (%t) PASS test %x", $time, simulation_verification.op2[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);
					`endif
				end
				else if (curr_active_state.alu_ctl[simulation_verification.active_list_id[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]] == ALUCTL_MTC0_FAIL)
				begin
					`ifdef SIMULATION
						$display("%m (%t) FAIL test %x", $time, simulation_verification.op2[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);
					`endif
				end
				pc_event(simulation_verification.pc[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]); 

				if (simulation_verification.uses_rw[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]])
					wb_event(simulation_verification.rw_addr[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]], simulation_verification.data[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);

				if (simulation_verification.is_load[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]])
					ls_event(READ, simulation_verification.mem_addr[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]], simulation_verification.data[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);
				if (simulation_verification.is_store[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]])
					ls_event(WRITE, simulation_verification.mem_addr[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]], simulation_verification.data[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]]);
			end
		end
	end
`endif

endmodule
