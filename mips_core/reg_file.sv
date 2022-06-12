/*
 * reg_file.sv
 * Author: Zinsser Zhang
 * Last Revision: 04/09/2018
 *
 * A 32-bit wide, 32-word deep register file with two asynchronous read port
 * and one synchronous write port.
 *
 * Register file needs to output '0 if uses_r* signal is low. In this case,
 * either reg zero is requested for read or the register is unused.
 *
 * See wiki page "Branch and Jump" for details.
 */
`include "mips_core.svh"


interface reg_file_output_ifc ();
	logic valid; 
	logic [`ADDR_WIDTH - 1 : 0] pc; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rs;

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rt;

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rw; 

	logic is_load; 
	logic is_store; 

	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id; 
	logic color_bit; 

	modport in  (input valid, pc, phys_rs, phys_rt, phys_rw,
		active_list_id, color_bit, is_load, is_store);
	modport out (output valid, pc, phys_rs, phys_rt, phys_rw,
		active_list_id, color_bit, is_load, is_store);
endinterface

module reg_file (
	input clk,
	input rst_n,

	input logic load_store_queue_full, 
	input logic issue_queue_full,

	// Input from decoder
	pc_ifc.in pc_in, 
	decoder_output_ifc.in i_decoded,

	hazard_signals_ifc.in hazard_signal_in, 
	write_back_ifc.in i_alu_write_back,
	write_back_ifc.in i_load_write_back,
	rename_ifc.in curr_rename_state,
	active_state_ifc.in curr_active_state, 
	commit_state_ifc.in curr_commit_state, 
	branch_state_ifc.in curr_branch_state,
	commit_output_ifc.in commit_output_in, 

	active_state_ifc.out next_active_state,
	rename_ifc.out next_rename_state,
	reg_file_output_ifc.out out,

	output logic decode_hazard
);

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rw; 

	logic reg_jump_hazard; 
	logic active_list_hazard; 
	logic free_list_hazard; 
	logic branch_hazard; 
	logic load_store_hazard; 
	logic ds_miss; 

	always_comb
	begin
		active_list_hazard = curr_commit_state.entry_available_bit == '0;  
		free_list_hazard = (curr_rename_state.free_head_pointer == commit_output_in.free_tail_pointer && i_decoded.uses_rw); 
		reg_jump_hazard = i_decoded.is_jump_reg & !curr_rename_state.m_reg_file_valid_bit[curr_rename_state.rename_buffer[i_decoded.rs_addr]]; 
		branch_hazard = (curr_branch_state.valid == {`BRANCH_NUM{1'b1}}) & i_decoded.is_branch_jump & !i_decoded.is_jump; 
		load_store_hazard = load_store_queue_full & i_decoded.is_mem_access; 
		ds_miss = hazard_signal_in.ic_miss & i_decoded.is_branch_jump; 

		decode_hazard = active_list_hazard | free_list_hazard | reg_jump_hazard | branch_hazard | load_store_hazard | issue_queue_full | ds_miss; 

		phys_rw = '0; 

		if (!rst_n)
		begin
			for (int i = 0; i < `REG_NUM; i++)
			begin
				next_rename_state.rename_buffer[i - 1] = i[$clog2(`REG_NUM) - 1 : 0]; 
			end

			for (int i = 0; i < `PHYS_REG_NUM; i++)
			begin
				next_rename_state.free_list[i] = i[`PHYS_REG_NUM_INDEX - 1 : 0];  
			end

			next_rename_state.free_head_pointer = `REG_NUM; 
			next_rename_state.merged_reg_file = '{default: 0};
			next_rename_state.m_reg_file_valid_bit = '0;
			next_rename_state.reverse_rename_map = '{default: 0};
			next_rename_state.branch_decoded_hazard = '0; 

			next_active_state.reclaim_list = '{default: 0}; 
			next_active_state.uses_rw = '{default: 0};
			next_active_state.rw_addr = '{default: 0};
			next_active_state.is_store = '{default: 0}; 
			next_active_state.is_load = '{default: 0}; 
			next_active_state.color_bit = '{default: 0}; 
			next_active_state.pc = '{default: 0}; 
			next_active_state.youngest_inst_pointer = 0; 
			next_active_state.global_color_bit = 1'b0; 

		end
		else 
		begin
			next_rename_state.branch_decoded_hazard = curr_rename_state.branch_decoded_hazard; 
			next_rename_state.free_head_pointer = curr_rename_state.free_head_pointer; 
			next_rename_state.rename_buffer = curr_rename_state.rename_buffer; 
			next_rename_state.merged_reg_file = curr_rename_state.merged_reg_file; 
			next_rename_state.m_reg_file_valid_bit = curr_rename_state.m_reg_file_valid_bit; 
			next_rename_state.free_list = curr_rename_state.free_list; 
			next_rename_state.reverse_rename_map = curr_rename_state.reverse_rename_map; 

			next_active_state.reclaim_list = curr_active_state.reclaim_list; 
			next_active_state.is_store = curr_active_state.is_store; 
			next_active_state.is_load = curr_active_state.is_load;
			next_active_state.uses_rw = curr_active_state.uses_rw; 
			next_active_state.rw_addr = curr_active_state.rw_addr; 
			next_active_state.color_bit = curr_active_state.color_bit; 
			next_active_state.global_color_bit = curr_active_state.global_color_bit; 
			next_active_state.pc = curr_active_state.pc; 
			next_active_state.youngest_inst_pointer = curr_active_state.youngest_inst_pointer; 
		end

		if (!decode_hazard && i_decoded.valid)
		begin
			if (i_decoded.uses_rw)
			begin
				phys_rw = curr_rename_state.free_list[curr_rename_state.free_head_pointer]; 

				next_rename_state.m_reg_file_valid_bit[phys_rw] = 1'b0;  
				next_rename_state.rename_buffer[i_decoded.rw_addr] = phys_rw; 
				next_rename_state.free_head_pointer = curr_rename_state.free_head_pointer + 1'b1;  
				next_rename_state.reverse_rename_map[phys_rw] = i_decoded.rw_addr;

				next_active_state.reclaim_list[curr_active_state.youngest_inst_pointer] = curr_rename_state.rename_buffer[i_decoded.rw_addr]; 
			end

			if (i_decoded.is_branch_jump && !i_decoded.is_jump)
				next_rename_state.branch_decoded_hazard = 1'b1; 
			else 
				next_rename_state.branch_decoded_hazard = 1'b0; 

			next_active_state.color_bit[curr_active_state.youngest_inst_pointer] = curr_active_state.global_color_bit; 
			next_active_state.pc[curr_active_state.youngest_inst_pointer] = pc_in.pc; 
			next_active_state.is_load[curr_active_state.youngest_inst_pointer] = i_decoded.mem_action == READ & i_decoded.is_mem_access; 
			next_active_state.is_store[curr_active_state.youngest_inst_pointer] = i_decoded.mem_action == WRITE & i_decoded.is_mem_access; 
			next_active_state.uses_rw[curr_active_state.youngest_inst_pointer] = i_decoded.uses_rw; 
			next_active_state.rw_addr[curr_active_state.youngest_inst_pointer] = phys_rw;
			next_active_state.youngest_inst_pointer = curr_active_state.youngest_inst_pointer + 1'b1; 
			if (next_active_state.youngest_inst_pointer == 0) next_active_state.global_color_bit = !curr_active_state.global_color_bit; 
		end


		if (i_alu_write_back.valid && i_alu_write_back.uses_rw)
		begin
			next_rename_state.merged_reg_file[i_alu_write_back.rw_addr] = i_alu_write_back.rw_data; 
			next_rename_state.m_reg_file_valid_bit[i_alu_write_back.rw_addr] = 1'b1; 
		end

		if (i_load_write_back.valid && i_load_write_back.uses_rw)
		begin
			next_rename_state.merged_reg_file[i_load_write_back.rw_addr] = i_load_write_back.rw_data; 
			next_rename_state.m_reg_file_valid_bit[i_load_write_back.rw_addr] = 1'b1;
		end

		if (commit_output_in.reclaim_valid)
		begin
			next_rename_state.free_list[commit_output_in.free_tail_pointer] = commit_output_in.reclaim_reg; 
		end

	end


	always_comb
	begin
		out.valid = !decode_hazard && i_decoded.valid; 
		
		out.phys_rs = curr_rename_state.rename_buffer[i_decoded.rs_addr]; 
		out.phys_rt = curr_rename_state.rename_buffer[i_decoded.rt_addr]; 

		out.is_load = i_decoded.mem_action == READ & i_decoded.is_mem_access;
		out.is_store = i_decoded.mem_action == WRITE & i_decoded.is_mem_access; 

		out.active_list_id = curr_active_state.youngest_inst_pointer; 
		out.color_bit = curr_active_state.global_color_bit; 
	end



`ifdef SIMULATION
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] prev_inst; 
	always_ff @(posedge clk)
	begin
		prev_inst <= curr_active_state.youngest_inst_pointer; 
		if (ds_miss && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("delay_slot_miss");
		if (active_list_hazard && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("active_list_full");
		if (load_store_hazard && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("load_store_queue_full");
		if (reg_jump_hazard && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("reg_jump_hazard");
		if (branch_hazard && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("dec_branch");
		if (free_list_hazard && prev_inst != curr_active_state.youngest_inst_pointer) stats_event("free_list_full");
	end
`endif

endmodule
