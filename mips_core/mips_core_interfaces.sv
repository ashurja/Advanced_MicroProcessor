/*
 * mips_core_interfaces.sv
 * Author: Zinsser Zhang
 * Last Revision: 04/09/2018
 *
 * These are interfaces that are not the input or output of one specific unit.
 *
 * See wiki page "Systemverilog Primer" section interfaces for details.
 */
`include "mips_core.svh"


interface active_state_ifc (); 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] reclaim_list [`ACTIVE_LIST_SIZE];
	logic [`ADDR_WIDTH - 1 : 0] pc [`ACTIVE_LIST_SIZE]; 
	logic global_color_bit; 
	logic color_bit [`ACTIVE_LIST_SIZE]; 
	logic uses_rw [`ACTIVE_LIST_SIZE]; 
	logic is_store [`ACTIVE_LIST_SIZE];
	logic is_load [`ACTIVE_LIST_SIZE];  
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] rw_addr[`ACTIVE_LIST_SIZE]; 
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] youngest_inst_pointer; 

	modport in (input reclaim_list, uses_rw, rw_addr, is_store,
		youngest_inst_pointer, is_load, pc, color_bit, global_color_bit); 
	modport out (output reclaim_list, uses_rw, rw_addr, is_store,
		youngest_inst_pointer, is_load, pc, color_bit, global_color_bit); 
endinterface

interface rename_ifc (); 
    logic branch_decoded_hazard; 
	logic [`REG_NUM_INDEX - 1 : 0] reverse_rename_map [`PHYS_REG_NUM]; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] rename_buffer [`REG_NUM]; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_head_pointer; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_list [`PHYS_REG_NUM]; 
	logic [`DATA_WIDTH - 1 : 0] merged_reg_file [`PHYS_REG_NUM]; 
	logic [`PHYS_REG_NUM - 1 : 0] m_reg_file_valid_bit; 


	modport in (input merged_reg_file, m_reg_file_valid_bit, free_list,
		rename_buffer, free_head_pointer, reverse_rename_map, branch_decoded_hazard); 
	modport out (output merged_reg_file, m_reg_file_valid_bit, free_list,
		rename_buffer, free_head_pointer, reverse_rename_map, branch_decoded_hazard); 

endinterface

interface load_pc_ifc ();
	logic we;	// Write Enable
	logic [`ADDR_WIDTH - 1 : 0] new_pc;

	modport in  (input we, new_pc);
	modport out (output we, new_pc);
endinterface

interface pc_ifc ();
	logic [`ADDR_WIDTH - 1 : 0] pc;

	modport in  (input pc);
	modport out (output pc);
endinterface

interface cache_output_ifc ();
	logic valid;	// Output Valid
	logic [`DATA_WIDTH - 1 : 0] data;

	modport in  (input valid, data);
	modport out (output valid, data);
endinterface

interface d_cache_controls_ifc (); 
	logic bypass_possible; 
	logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] bypass_index; 
	logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] dispatch_index; 
	logic NOP; 
	modport in (input bypass_possible, bypass_index, NOP, dispatch_index); 
	modport out (output bypass_possible, bypass_index, NOP, dispatch_index); 
endinterface

interface branch_decoded_ifc ();
	logic valid;	// High means the instruction is a branch or a jump
	logic is_jump;	// High means the instruction is a jump
	logic [`ADDR_WIDTH - 1 : 0] target;

	mips_core_pkg::BranchOutcome prediction;
	logic [`ADDR_WIDTH - 1 : 0] recovery_target;

	modport decode (output valid, is_jump, target,
		input prediction, recovery_target);
	modport hazard (output prediction, recovery_target,
		input valid, is_jump, target);
endinterface


interface branch_result_ifc ();
	logic valid;
	logic [`ADDR_WIDTH - 1 : 0] pc;
	mips_core_pkg::BranchOutcome prediction;
	mips_core_pkg::BranchOutcome outcome;
	logic [`ADDR_WIDTH - 1 : 0] recovery_target;
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id; 
	logic color_bit; 

	modport in  (input valid, pc, prediction, outcome, recovery_target, branch_id, color_bit);
	modport out (output valid, pc, prediction, outcome, recovery_target, branch_id, color_bit);
endinterface


interface inst_commit_ifc ();
	logic valid; 
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id; 

	modport in  (input valid, active_list_id);
	modport out (output valid, active_list_id);
endinterface

interface write_back_ifc (); 
	logic valid; 
	logic uses_rw;	// Write Enable
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] rw_addr;
	logic [`DATA_WIDTH - 1 : 0] rw_data;

	modport in  (input valid, uses_rw, rw_addr, rw_data);
	modport out (output valid, uses_rw, rw_addr, rw_data);
endinterface


interface hazard_signals_ifc (); 

	logic ic_miss; 
	logic dc_miss; 
	logic branch_miss; 
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id; 
	logic color_bit; 

	modport in (input ic_miss, dc_miss, branch_miss, color_bit, branch_id); 
	modport out (output ic_miss, dc_miss, branch_miss, color_bit, branch_id);
endinterface


interface hazard_control_ifc ();
	// Stall signal has higher priority
	logic flush;	// Flush signal of the previous stage
	logic stall;	// Stall signal of the next stage

	modport in  (input flush, stall);
	modport out (output flush, stall);
endinterface

interface simulation_verification_ifc (); 
	logic valid; 
	logic [`ADDR_WIDTH - 1 : 0] pc; 
	logic is_store; 
	logic is_load; 
	logic [`ADDR_WIDTH - 1 : 0] mem_addr; 
	logic uses_rw; 
	logic [`REG_NUM_INDEX - 1 : 0] rw_addr; 
	logic [`DATA_WIDTH - 1 : 0] data; 

	modport in (input valid, pc, uses_rw, rw_addr, data, is_load, is_store, mem_addr); 
	modport out (output valid, pc, uses_rw, rw_addr, data, is_load, is_store, mem_addr); 
endinterface
