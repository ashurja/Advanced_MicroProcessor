/*
 * branch_controller.sv
 * Author: Zinsser Zhang
 * Last Revision: 04/08/2018
 *
 * These are glue circuits in each stage. They select data between different
 * sources for particular signals (e.g. alu's op2). They also re-combine the
 * signals to different interfaces that are passed to the next stage or hazard
 * controller.
 */
`include "mips_core.svh"

module decode_stage_glue (
	decoder_output_ifc.in i_decoded,
	reg_file_output_ifc.in i_reg_data,
	rename_ifc.in next_rename_state, 
	rename_ifc.in curr_rename_state, 
	issue_input_ifc.in buffered_issue_state,

	branch_decoded_ifc.decode branch_decoded,	// Contains both i/o
	issue_input_ifc.out o_decode_pass_through
); 

	always_comb
	begin

		o_decode_pass_through.valid[0] = buffered_issue_state.valid[0];  
		o_decode_pass_through.phys_rs[0] = buffered_issue_state.phys_rs[0];  
		o_decode_pass_through.phys_rt[0] = buffered_issue_state.phys_rt[0];    

		o_decode_pass_through.uses_rs[0] = buffered_issue_state.uses_rs[0];  
		o_decode_pass_through.uses_rt[0] = buffered_issue_state.uses_rt[0];  
		o_decode_pass_through.uses_immediate[0] = buffered_issue_state.uses_immediate[0];  

		o_decode_pass_through.immediate[0] = buffered_issue_state.immediate[0];  

		o_decode_pass_through.is_branch[0] = buffered_issue_state.is_branch[0]; 
		o_decode_pass_through.prediction[0] = buffered_issue_state.prediction[0];  
		o_decode_pass_through.recovery_target[0] = buffered_issue_state.recovery_target[0];  

		o_decode_pass_through.is_mem_access[0] = buffered_issue_state.is_mem_access[0];  
		o_decode_pass_through.mem_action[0] = buffered_issue_state.mem_action[0];  
		o_decode_pass_through.active_list_id[0] = buffered_issue_state.active_list_id[0];  


		o_decode_pass_through.valid[1] = '0;   
		o_decode_pass_through.phys_rs[1] = '0;   
		o_decode_pass_through.phys_rt[1] = '0;    

		o_decode_pass_through.uses_rs[1] = '0;   
		o_decode_pass_through.uses_rt[1] = '0;   
		o_decode_pass_through.uses_immediate[1] = '0;   

		o_decode_pass_through.immediate[1] = '0;   

		o_decode_pass_through.is_branch[1] = '0;   
		o_decode_pass_through.prediction[1] = '0;   
		o_decode_pass_through.recovery_target[1] = '0;   

		o_decode_pass_through.is_mem_access[1] = '0;   
		o_decode_pass_through.mem_action[1] = '0;    
		o_decode_pass_through.active_list_id[1] = '0;   

		if (curr_rename_state.branch_decoded_hazard)
		begin
			o_decode_pass_through.valid[1] = i_reg_data.valid; 
			o_decode_pass_through.phys_rs[1] = i_reg_data.phys_rs; 
			o_decode_pass_through.phys_rt[1] = i_reg_data.phys_rt; 

			o_decode_pass_through.uses_rs[1] = i_decoded.uses_rs; 
			o_decode_pass_through.uses_rt[1] = i_decoded.uses_rt; 
			o_decode_pass_through.uses_immediate[1] = i_decoded.uses_immediate; 

			o_decode_pass_through.immediate[1] = i_decoded.immediate; 

			o_decode_pass_through.is_branch[1] = i_decoded.is_branch_jump & ~i_decoded.is_jump;
			o_decode_pass_through.prediction[1] = branch_decoded.prediction; 
			o_decode_pass_through.recovery_target[1] = branch_decoded.recovery_target; 

			o_decode_pass_through.is_mem_access[1] = i_decoded.is_mem_access; 
			o_decode_pass_through.mem_action[1] = i_decoded.mem_action; 
			o_decode_pass_through.active_list_id[1] = i_reg_data.active_list_id; 
		end
		else 
		begin
			o_decode_pass_through.valid[0] = i_reg_data.valid; 
			o_decode_pass_through.phys_rs[0] = i_reg_data.phys_rs; 
			o_decode_pass_through.phys_rt[0] = i_reg_data.phys_rt; 

			o_decode_pass_through.uses_rs[0] = i_decoded.uses_rs; 
			o_decode_pass_through.uses_rt[0] = i_decoded.uses_rt; 
			o_decode_pass_through.uses_immediate[0] = i_decoded.uses_immediate; 

			o_decode_pass_through.immediate[0] = i_decoded.immediate; 

			o_decode_pass_through.is_branch[0] = i_decoded.is_branch_jump & ~i_decoded.is_jump;
			o_decode_pass_through.prediction[0] = branch_decoded.prediction; 
			o_decode_pass_through.recovery_target[0] = branch_decoded.recovery_target; 

			o_decode_pass_through.is_mem_access[0] = i_decoded.is_mem_access; 
			o_decode_pass_through.mem_action[0] = i_decoded.mem_action; 
			o_decode_pass_through.active_list_id[0] = i_reg_data.active_list_id; 
		end

		o_decode_pass_through.phys_rs_valid[0] = next_rename_state.m_reg_file_valid_bit[o_decode_pass_through.phys_rs[0]]; 
		o_decode_pass_through.phys_rt_valid[0] = next_rename_state.m_reg_file_valid_bit[o_decode_pass_through.phys_rt[0]];
		o_decode_pass_through.phys_rs_valid[1] = next_rename_state.m_reg_file_valid_bit[o_decode_pass_through.phys_rs[1]]; 
		o_decode_pass_through.phys_rt_valid[1] = next_rename_state.m_reg_file_valid_bit[o_decode_pass_through.phys_rt[1]];

		branch_decoded.valid =   i_decoded.is_branch_jump;
		branch_decoded.is_jump = i_decoded.is_jump;
		branch_decoded.target =  i_decoded.is_jump_reg
			? curr_rename_state.merged_reg_file[o_decode_pass_through.phys_rs[0]][`ADDR_WIDTH - 1 : 0]
			: i_decoded.branch_target;
	end
endmodule

module mem_stage_glue (
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
	cache_output_ifc.in d_cache_output, 
	d_cache_controls_ifc.in o_d_cache_controls, 

	write_back_ifc.out o_load_write_back, 
	inst_commit_ifc.out o_mem_commit,
	output o_done
);
	always_comb
	begin
		o_done = 1'b1; 

		o_mem_commit.valid = 1'b0; 
		o_mem_commit.active_list_id = '0; 

		o_load_write_back.valid = '0; 
		o_load_write_back.uses_rw  = '0; 
		o_load_write_back.rw_addr = '0; 
		o_load_write_back.rw_data = '0; 

		if (o_d_cache_controls.valid)
		begin
			if (o_d_cache_controls.mem_action == WRITE)
			begin
				o_done = d_cache_output.valid;   

				o_mem_commit.valid = d_cache_output.valid;
				o_mem_commit.active_list_id = curr_store_queue.active_list_id[o_d_cache_controls.dispatch_index]; 
			end

			else 
			begin
				o_done = (o_d_cache_controls.bypass_possible) ? 1'b1 : d_cache_output.valid; 

				o_load_write_back.valid = (o_d_cache_controls.NOP) ? 1'b0 : d_cache_output.valid | o_d_cache_controls.bypass_possible;
				o_load_write_back.uses_rw = curr_active_state.uses_rw[curr_load_queue.active_list_id[o_d_cache_controls.dispatch_index]]; 
				o_load_write_back.rw_addr = curr_active_state.rw_addr[curr_load_queue.active_list_id[o_d_cache_controls.dispatch_index]]; 
				o_load_write_back.rw_data = (o_d_cache_controls.bypass_possible) ? curr_store_queue.sw_data[o_d_cache_controls.bypass_index] : d_cache_output.data; 

				o_mem_commit.valid = o_load_write_back.valid;
				o_mem_commit.active_list_id = curr_load_queue.active_list_id[o_d_cache_controls.dispatch_index];
			end
		end
	end

endmodule