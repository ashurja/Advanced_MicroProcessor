module data_struct_update (
    input clk, 
	input rst_n, 

	hazard_signals_ifc.in hazard_signal_in, 

	d_cache_controls_ifc.in i_d_cache_controls, 
	scheduler_output_ifc.in i_scheduler, 

	commit_output_ifc.in i_commit_out, 
	write_back_ifc.in i_load_write_back, 
	reg_file_output_ifc.in i_reg_data,

	issue_input_ifc.in i_decode_pass_through, 

    rename_ifc.in next_rename_state, 
    active_state_ifc.in next_active_state, 
    commit_state_ifc.in next_commit_state, 
    integer_issue_queue_ifc.in next_int_queue, 
    memory_issue_queue_ifc.in next_mem_queue, 
	branch_state_ifc.in next_branch_state, 
	load_queue_ifc.in next_load_queue, 
	store_queue_ifc.in next_store_queue,
	branch_controls_ifc.in next_branch_controls,

	rename_ifc.in misprediction_rename_state, 
	active_state_ifc.in misprediction_active_state, 
	integer_issue_queue_ifc.in misprediction_int_queue, 
	memory_issue_queue_ifc.in misprediction_mem_queue, 
	load_queue_ifc.in misprediction_load_queue, 
	store_queue_ifc.in misprediction_store_queue, 
	branch_state_ifc.in misprediction_branch_state, 
	branch_controls_ifc.in misprediction_branch_controls,

	issue_input_ifc.out buffered_issue_state, 
    rename_ifc.out curr_rename_state, 
    active_state_ifc.out curr_active_state, 
    commit_state_ifc.out curr_commit_state, 
    integer_issue_queue_ifc.out curr_int_queue, 
    memory_issue_queue_ifc.out curr_mem_queue,
	branch_state_ifc.out curr_branch_state,
	branch_controls_ifc.out curr_branch_controls,
	load_queue_ifc.out curr_load_queue, 
	store_queue_ifc.out curr_store_queue
);

	logic [`ACTIVE_LIST_SIZE - 1 : 0] commit_next_ready_to_commit; 
	always_comb
	begin
		commit_next_ready_to_commit = next_commit_state.ready_to_commit; 

		for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
		begin
			if (i_commit_out.commit_valid)
			begin
				if (i <= i_commit_out.last_valid_commit_idx)
				begin
					commit_next_ready_to_commit[curr_commit_state.oldest_inst_pointer + i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0]] = 1'b0; 
				end
			end
		end
	end

    always_ff @(posedge clk) 
    begin : UPDATE_COMMIT_STATE

		curr_commit_state.ready_to_commit <= commit_next_ready_to_commit; 
		curr_commit_state.entry_available_bit <= next_commit_state.entry_available_bit; 
		curr_commit_state.branch_read_pointer <= next_commit_state.branch_read_pointer; 
		curr_commit_state.oldest_inst_pointer <= next_commit_state.oldest_inst_pointer; 
		curr_commit_state.free_tail_pointer <= next_commit_state.free_tail_pointer; 
		curr_commit_state.load_commit_pointer <= next_commit_state.load_commit_pointer;
		curr_commit_state.store_commit_pointer <= next_commit_state.store_commit_pointer;

		if (hazard_signal_in.branch_miss)
		begin
			curr_commit_state.entry_available_bit[misprediction_active_state.youngest_inst_pointer] <= 1'b0; 
			curr_commit_state.ready_to_commit[misprediction_active_state.youngest_inst_pointer] <= 1'b0; 
		end
		else 
		begin
			curr_commit_state.entry_available_bit[curr_active_state.youngest_inst_pointer] <= 1'b0; 
			curr_commit_state.ready_to_commit[curr_active_state.youngest_inst_pointer] <= 1'b0; 
		end

			
	end


	logic [`BRANCH_NUM - 1 : 0] branch_next_valid; 
	int branch; 
	always_comb
	begin
		branch = 0; 

		if (hazard_signal_in.branch_miss)
		begin
			branch_next_valid = misprediction_branch_state.valid; 
		end
		else 
		begin
			branch_next_valid = next_branch_state.valid; 
		end

		for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
        begin
            if (i_commit_out.commit_valid)
            begin
                if (i_commit_out.branch_valid[i] && i <= i_commit_out.last_valid_commit_idx)
                    begin
						branch_next_valid[curr_commit_state.branch_read_pointer + branch[`BRANCH_NUM_INDEX - 1 : 0]] = 1'b0;
						branch++; 
					end
            end
        end
	end

	always_ff @(posedge clk)
	begin : UPDATE_BRANCH_STATE

		if (hazard_signal_in.branch_miss)
		begin
			curr_branch_state.write_pointer <= misprediction_branch_state.write_pointer; 
		end

		else 
		begin
			curr_branch_state.write_pointer <= next_branch_state.write_pointer; 
		end

		curr_branch_state.ds_valid <= next_branch_state.ds_valid; 
		curr_branch_state.GHR <= next_branch_state.GHR; 
		curr_branch_state.free_head_pointer <= next_branch_state.free_head_pointer; 
		curr_branch_state.rename_buffer <= next_branch_state.rename_buffer; 
		curr_branch_state.branch_id <= next_branch_state.branch_id; 

		curr_branch_state.valid = branch_next_valid; 
	end

	always_ff @(posedge clk)
	begin : UPDATE_BRANCH_CONTROLS

		if (hazard_signal_in.branch_miss)
		begin
			curr_branch_controls.GHR <= misprediction_branch_controls.GHR;  
		end

		else 
		begin
			curr_branch_controls.GHR <= next_branch_controls.GHR; 
		end
	end


	always_ff @(posedge clk) 
	begin : UPDATE_ACTIVE_STATE
		if (hazard_signal_in.branch_miss)
		begin
			curr_active_state.youngest_inst_pointer <= misprediction_active_state.youngest_inst_pointer; 
			curr_active_state.global_color_bit <= misprediction_active_state.global_color_bit; 
		end

		else 
		begin
			curr_active_state.global_color_bit <= next_active_state.global_color_bit; 
			curr_active_state.youngest_inst_pointer <= next_active_state.youngest_inst_pointer; 
		end
		
		curr_active_state.pc <= next_active_state.pc; 
		curr_active_state.alu_ctl <= next_active_state.alu_ctl; 
		curr_active_state.color_bit <= next_active_state.color_bit; 
		curr_active_state.reclaim_list <= next_active_state.reclaim_list;
		curr_active_state.is_load <= next_active_state.is_load; 
		curr_active_state.is_store <= next_active_state.is_store; 
		curr_active_state.uses_rw <= next_active_state.uses_rw;
		curr_active_state.rw_addr <= next_active_state.rw_addr;
	end


    always_ff @(posedge clk) 
	begin : UPDATE_RENAME_STAGE

		if (hazard_signal_in.branch_miss)
		begin
			curr_rename_state.free_head_pointer <= misprediction_rename_state.free_head_pointer; 
			curr_rename_state.rename_buffer <= misprediction_rename_state.rename_buffer;
			curr_rename_state.branch_decoded_hazard <= 1'b0; 

			curr_rename_state.reverse_rename_map <= next_rename_state.reverse_rename_map; 
			curr_rename_state.merged_reg_file <= next_rename_state.merged_reg_file;
			curr_rename_state.free_list <= next_rename_state.free_list; 
			curr_rename_state.m_reg_file_valid_bit <= next_rename_state.m_reg_file_valid_bit; 
		end
		else 
		begin
			curr_rename_state.branch_decoded_hazard <= next_rename_state.branch_decoded_hazard; 
			curr_rename_state.reverse_rename_map <= next_rename_state.reverse_rename_map; 
			curr_rename_state.rename_buffer <= next_rename_state.rename_buffer;
			curr_rename_state.free_head_pointer <= next_rename_state.free_head_pointer; 
			curr_rename_state.merged_reg_file <= next_rename_state.merged_reg_file;
			curr_rename_state.free_list <= next_rename_state.free_list; 
			curr_rename_state.m_reg_file_valid_bit <= next_rename_state.m_reg_file_valid_bit; 
		end
	end


	always_ff @(posedge clk) 
	begin
		buffered_issue_state.valid <= i_decode_pass_through.valid; 
		buffered_issue_state.phys_rs <= i_decode_pass_through.phys_rs; 
		buffered_issue_state.phys_rs_valid <= i_decode_pass_through.phys_rs_valid;
		buffered_issue_state.phys_rt <= i_decode_pass_through.phys_rt;
		buffered_issue_state.phys_rt_valid <= i_decode_pass_through.phys_rt_valid; 
		buffered_issue_state.uses_rs <= i_decode_pass_through.uses_rs; 
		buffered_issue_state.uses_rt <= i_decode_pass_through.uses_rt;
		buffered_issue_state.uses_immediate <= i_decode_pass_through.uses_immediate;
		buffered_issue_state.immediate <= i_decode_pass_through.immediate; 
		buffered_issue_state.is_branch <= i_decode_pass_through.is_branch; 
		buffered_issue_state.prediction <= i_decode_pass_through.prediction; 
		buffered_issue_state.recovery_target <= i_decode_pass_through.recovery_target; 
		buffered_issue_state.is_mem_access <= i_decode_pass_through.is_mem_access; 
		buffered_issue_state.mem_action <= i_decode_pass_through.mem_action; 
		buffered_issue_state.active_list_id <= i_decode_pass_through.active_list_id;
	end

    always_ff @(posedge clk) 
    begin : UPDATE_ISSUE_STAGE
		if (hazard_signal_in.branch_miss)
		begin
			curr_int_queue.entry_available_bit <= misprediction_int_queue.entry_available_bit; 
			curr_mem_queue.entry_available_bit <= misprediction_mem_queue.entry_available_bit;  
		end
		else 
		begin
        	curr_int_queue.entry_available_bit <= next_int_queue.entry_available_bit; 
			curr_mem_queue.entry_available_bit <= next_mem_queue.entry_available_bit;  
		end

		curr_int_queue.src1 <= next_int_queue.src1;  
		curr_int_queue.ready_bit_src1 <= next_int_queue.ready_bit_src1; 
		curr_int_queue.src2 <= next_int_queue.src2; 
		curr_int_queue.ready_bit_src2 <= next_int_queue.ready_bit_src2; 
		curr_int_queue.immediate_data <= next_int_queue.immediate_data; 
		curr_int_queue.is_branch <= next_int_queue.is_branch;
		curr_int_queue.prediction <= next_int_queue.prediction; 
		curr_int_queue.recovery_target <= next_int_queue.recovery_target; 
		curr_int_queue.uses_rs <= next_int_queue.uses_rs; 
		curr_int_queue.uses_rt <= next_int_queue.uses_rt; 
		curr_int_queue.uses_immediate <= next_int_queue.uses_immediate; 
		curr_int_queue.active_list_id <= next_int_queue.active_list_id; 

		curr_mem_queue.src1 <= next_mem_queue.src1; 
		curr_mem_queue.ready_bit_src1 <= next_mem_queue.ready_bit_src1; 
		curr_mem_queue.sw_src <= next_mem_queue.sw_src; 
		curr_mem_queue.ready_bit_sw_src <= next_mem_queue.ready_bit_sw_src; 
		curr_mem_queue.immediate_data <= next_mem_queue.immediate_data;
		curr_mem_queue.mem_action <= next_mem_queue.mem_action; 
		curr_mem_queue.uses_rs <= next_mem_queue.uses_rs; 
		curr_mem_queue.active_list_id <= next_mem_queue.active_list_id; 

		if (i_scheduler.mem_valid) 
			curr_mem_queue.entry_available_bit[i_scheduler.agu_dispatch_index] <= 1'b1; 

		if (i_scheduler.int_valid)
			curr_int_queue.entry_available_bit[i_scheduler.alu_dispatch_index] <= 1'b1; 
    end


	logic [`LOAD_STORE_SIZE - 1 : 0] load_next_entry_available; 
	logic [`LOAD_STORE_SIZE - 1 : 0] store_next_entry_available;

	logic [`LOAD_STORE_SIZE - 1 : 0] store_next_valid; 
	logic [`LOAD_STORE_SIZE - 1 : 0] load_next_valid; 

	int load, store; 
	always_comb
	begin
		load = 0; 
		store = 0; 

		if (hazard_signal_in.branch_miss)
		begin
			load_next_entry_available = misprediction_load_queue.entry_available_bit; 
			store_next_entry_available = misprediction_store_queue.entry_available_bit; 
		end
		else 
		begin
			load_next_entry_available = next_load_queue.entry_available_bit; 
			store_next_entry_available = next_store_queue.entry_available_bit; 
		end

		store_next_valid = next_store_queue.valid; 
		load_next_valid = next_load_queue.valid; 

		if (!hazard_signal_in.dc_miss && i_d_cache_controls.valid)
		begin
			if (i_d_cache_controls.mem_action == READ)
			begin
				load_next_valid[i_d_cache_controls.dispatch_index] = 1'b0; 
			end
		end

		for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
        begin
            if (i_commit_out.commit_valid)
            begin
                if (i_commit_out.load_valid[i] && i <= i_commit_out.last_valid_commit_idx)
					begin
						load_next_entry_available[curr_commit_state.load_commit_pointer + load[`LOAD_STORE_SIZE_INDEX - 1 : 0]] = 1'b1; 
						load++; 
					end
					
                if (i_commit_out.store_valid[i] && i <= i_commit_out.last_valid_commit_idx)
                    begin
						store_next_entry_available[curr_commit_state.store_commit_pointer + store[`LOAD_STORE_SIZE_INDEX - 1 : 0]] = 1'b1; 
						store_next_valid[curr_commit_state.store_commit_pointer + store[`LOAD_STORE_SIZE_INDEX - 1 : 0]] = 1'b0;
						store++; 
					end
            end
        end

	end


	always_ff @(posedge clk)
	begin : UPDATE_LOAD_STORE_STAGE
		if (hazard_signal_in.branch_miss)
		begin
			curr_load_queue.active_list_id <= misprediction_load_queue.active_list_id; 
			curr_load_queue.entry_write_pointer <= misprediction_load_queue.entry_write_pointer; 

			curr_store_queue.active_list_id <= misprediction_store_queue.active_list_id; 
			curr_store_queue.entry_write_pointer <= misprediction_store_queue.entry_write_pointer; 
		end
		else 
		begin
			curr_load_queue.active_list_id <= next_load_queue.active_list_id; 
			curr_load_queue.entry_write_pointer <= next_load_queue.entry_write_pointer; 

			curr_store_queue.active_list_id <= next_store_queue.active_list_id; 
			curr_store_queue.entry_write_pointer <= next_store_queue.entry_write_pointer; 
		end

		curr_load_queue.entry_available_bit <= load_next_entry_available; 
		curr_load_queue.mem_addr <= next_load_queue.mem_addr; 
		curr_load_queue.valid <= load_next_valid;

		curr_store_queue.entry_available_bit <= store_next_entry_available; 
		curr_store_queue.sw_data <= next_store_queue.sw_data; 
		curr_store_queue.mem_addr <= next_store_queue.mem_addr; 
		curr_store_queue.read_pointer <= next_store_queue.read_pointer; 
		curr_store_queue.valid <= store_next_valid; 

	end

endmodule