`include "mips_core.svh"

interface scheduler_output_ifc (); 

    logic int_valid; 
    logic mem_valid; 

    logic [`INT_QUEUE_SIZE_INDEX - 1 : 0] alu_dispatch_index; 
    logic [`MEM_QUEUE_SIZE_INDEX - 1 : 0] agu_dispatch_index; 

    modport in (input int_valid, mem_valid, alu_dispatch_index, agu_dispatch_index); 
    modport out (output int_valid, mem_valid, alu_dispatch_index, agu_dispatch_index); 

endinterface


module scheduler (

    hazard_signals_ifc.in hazard_signal_in, 
    memory_issue_queue_ifc.in curr_mem_queue,
	integer_issue_queue_ifc.in curr_int_queue,
    rename_ifc.in curr_rename_state,
    alu_output_ifc.in i_alu_output,
	active_state_ifc.in curr_active_state,	

    scheduler_output_ifc.out o_scheduler, 
	write_back_ifc.out o_alu_write_back, 
    alu_input_ifc.out o_alu_input,
	agu_input_ifc.out o_agu_input,
    branch_result_ifc.out o_branch_result,
	inst_commit_ifc.out o_int_commit
); 

    logic [`MEM_QUEUE_SIZE_INDEX - 1 : 0] mem_issue_queue_read_pointer; 

    logic alu_dispatch_match; 
    logic [`INT_QUEUE_SIZE_INDEX - 1 : 0] alu_dispatch_index;
	logic [`INT_QUEUE_SIZE - 1 : 0] dispatch_alu;

    logic agu_dispatch_match; 
    logic [`MEM_QUEUE_SIZE - 1 : 0] dispatch_agu; 
    logic [`MEM_QUEUE_SIZE_INDEX - 1 : 0] agu_dispatch_index; 

    priority_encoder# (
		.m(`INT_QUEUE_SIZE),
		.n(`INT_QUEUE_SIZE_INDEX)
	) dispatch_alu_retriever (
		.x(dispatch_alu),
		.bottom_up(1'b1),
		.valid_in(alu_dispatch_match),
		.y(alu_dispatch_index)
	);


    priority_encoder# (
		.m(`MEM_QUEUE_SIZE),
		.n(`MEM_QUEUE_SIZE_INDEX)
    ) dispatch_agu_retriever (
		.x(dispatch_agu),
		.bottom_up(1'b1),
		.valid_in(agu_dispatch_match),
		.y(agu_dispatch_index)
	);

    always_comb
    begin
        for (int i = 0; i < `INT_QUEUE_SIZE; i++)
        begin
            dispatch_alu[i] = curr_int_queue.ready_bit_src1[i] & curr_int_queue.ready_bit_src2[i] & !curr_int_queue.entry_available_bit[i];
        end

        for (int i = 0; i < `MEM_QUEUE_SIZE; i++)
        begin
            dispatch_agu[i] = curr_mem_queue.ready_bit_src1[i] & curr_mem_queue.ready_bit_sw_src[i] & !curr_mem_queue.entry_available_bit[i];
        end
    end


	always_comb
	begin : handle_int
		o_alu_input.valid = alu_dispatch_match;
		o_alu_input.alu_ctl = curr_int_queue.alu_ctl[alu_dispatch_index];
		o_alu_input.op1 = curr_int_queue.uses_rs[alu_dispatch_index] ? curr_rename_state.merged_reg_file[curr_int_queue.src1[alu_dispatch_index]] : '0; 

		if (curr_int_queue.uses_immediate[alu_dispatch_index]) o_alu_input.op2 = curr_int_queue.immediate_data[alu_dispatch_index]; 
		else if (curr_int_queue.uses_rt[alu_dispatch_index]) o_alu_input.op2 = curr_rename_state.merged_reg_file[curr_int_queue.src2[alu_dispatch_index]]; 
        else o_alu_input.op2 = '0; 


        o_branch_result.valid = i_alu_output.valid & curr_int_queue.is_branch[alu_dispatch_index];
        o_branch_result.pc = curr_active_state.pc[curr_int_queue.active_list_id[alu_dispatch_index]]; 
        o_branch_result.color_bit = curr_active_state.color_bit[curr_int_queue.active_list_id[alu_dispatch_index]]; 
		o_branch_result.branch_id = curr_int_queue.active_list_id[alu_dispatch_index]; 
		o_branch_result.prediction = curr_int_queue.prediction[alu_dispatch_index]; 
		o_branch_result.outcome =    i_alu_output.branch_outcome; 
		o_branch_result.recovery_target =  curr_int_queue.recovery_target[alu_dispatch_index]; 


        o_alu_write_back.valid = i_alu_output.valid;
		o_alu_write_back.uses_rw = curr_active_state.uses_rw[curr_int_queue.active_list_id[alu_dispatch_index]]; 
		o_alu_write_back.rw_addr = curr_active_state.rw_addr[curr_int_queue.active_list_id[alu_dispatch_index]]; 
		o_alu_write_back.rw_data = i_alu_output.result;

	end

	always_comb
	begin : handle_mem
		o_agu_input.valid = agu_dispatch_match;  
        o_agu_input.op1 = curr_mem_queue.uses_rs[agu_dispatch_index] ? curr_rename_state.merged_reg_file[curr_mem_queue.src1[agu_dispatch_index]] : '0; 
		o_agu_input.op2 = curr_mem_queue.immediate_data[agu_dispatch_index]; 
	end


    always_comb
    begin
		o_int_commit.valid = i_alu_output.valid;
		o_int_commit.active_list_id = curr_int_queue.active_list_id[alu_dispatch_index]; 
    end


    always_comb 
    begin
        o_scheduler.int_valid = alu_dispatch_match; 
        o_scheduler.mem_valid = agu_dispatch_match; 

        o_scheduler.alu_dispatch_index = alu_dispatch_index; 
        o_scheduler.agu_dispatch_index = agu_dispatch_index; 
    end



endmodule 