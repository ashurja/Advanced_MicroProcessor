`include "mips_core.svh"

interface issue_input_ifc (); 
	logic valid [`ISSUE_SIZE]; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rs [`ISSUE_SIZE];  
	logic phys_rs_valid [`ISSUE_SIZE];  
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rt [`ISSUE_SIZE];  
	logic phys_rt_valid [`ISSUE_SIZE];  

	mips_core_pkg::AluCtl alu_ctl [`ISSUE_SIZE]; 

	logic uses_rs [`ISSUE_SIZE];  
	logic uses_rt [`ISSUE_SIZE];  
	logic uses_immediate [`ISSUE_SIZE];  

	logic [`DATA_WIDTH - 1 : 0] immediate [`ISSUE_SIZE]; 

	logic is_branch [`ISSUE_SIZE];  
	mips_core_pkg::BranchOutcome prediction [`ISSUE_SIZE]; 
	logic [`ADDR_WIDTH - 1 : 0] recovery_target [`ISSUE_SIZE];  

	logic is_mem_access [`ISSUE_SIZE];  
	mips_core_pkg::MemAccessType mem_action [`ISSUE_SIZE];  

	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`ISSUE_SIZE];  

	modport in (input valid, phys_rs, phys_rs_valid, phys_rt, phys_rt_valid, 
				alu_ctl, uses_rs, uses_rt, uses_immediate, 
				immediate, is_branch, prediction, recovery_target, 
				is_mem_access, mem_action, active_list_id); 
	modport out (output valid, phys_rs, phys_rs_valid, phys_rt, phys_rt_valid, 
				alu_ctl, uses_rs, uses_rt, uses_immediate, 
				immediate, is_branch, prediction, recovery_target, 
				is_mem_access, mem_action, active_list_id); 
endinterface


interface integer_issue_queue_ifc (); 

    logic [`INT_QUEUE_SIZE - 1 : 0] entry_available_bit; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] src1 [`INT_QUEUE_SIZE]; 
	logic ready_bit_src1 [`INT_QUEUE_SIZE]; 
    logic ready_bit_src2 [`INT_QUEUE_SIZE]; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] src2 [`INT_QUEUE_SIZE];
	logic [`DATA_WIDTH - 1 : 0] immediate_data [`INT_QUEUE_SIZE]; 


	mips_core_pkg::AluCtl alu_ctl [`INT_QUEUE_SIZE]; 

	logic is_branch [`INT_QUEUE_SIZE];
	mips_core_pkg::BranchOutcome prediction [`INT_QUEUE_SIZE];
	logic [`ADDR_WIDTH - 1 : 0] recovery_target [`INT_QUEUE_SIZE];

	logic uses_rs [`INT_QUEUE_SIZE]; 
	logic uses_rt [`INT_QUEUE_SIZE]; 
	logic uses_immediate [`INT_QUEUE_SIZE]; 

    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`INT_QUEUE_SIZE]; 

	modport in  (input entry_available_bit, src1, ready_bit_src1,
		src2, immediate_data, ready_bit_src2, alu_ctl, is_branch, prediction, recovery_target,
		uses_rs, uses_rt, uses_immediate, active_list_id);
	modport out  (output entry_available_bit, src1, ready_bit_src1,
		src2, immediate_data, ready_bit_src2, alu_ctl, is_branch, prediction, recovery_target,
		uses_rs, uses_rt, uses_immediate, active_list_id);
endinterface


interface memory_issue_queue_ifc (); 

	logic [`MEM_QUEUE_SIZE - 1 : 0] entry_available_bit; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] src1 [`MEM_QUEUE_SIZE]; 
	logic ready_bit_src1 [`MEM_QUEUE_SIZE]; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] sw_src [`MEM_QUEUE_SIZE];
	logic ready_bit_sw_src [`MEM_QUEUE_SIZE]; 
	logic [`DATA_WIDTH - 1 : 0] immediate_data [`MEM_QUEUE_SIZE]; 

	mips_core_pkg::MemAccessType mem_action [`MEM_QUEUE_SIZE]; 
	logic uses_rs [`MEM_QUEUE_SIZE]; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`MEM_QUEUE_SIZE]; 
    logic color_bit [`MEM_QUEUE_SIZE]; 


	modport in  (input entry_available_bit, src1, ready_bit_src1, 
		immediate_data, sw_src, ready_bit_sw_src,
		mem_action, uses_rs, active_list_id, color_bit);  
	modport out (output entry_available_bit, src1, ready_bit_src1, 
		immediate_data, sw_src, ready_bit_sw_src,
		mem_action, uses_rs, active_list_id, color_bit);  
endinterface


module issue (
    input rst_n, 

    issue_input_ifc.in issue_in,
	memory_issue_queue_ifc.in curr_mem_queue,
	integer_issue_queue_ifc.in curr_int_queue,
    hazard_signals_ifc.in hazard_signal_in, 
    branch_state_ifc.in curr_branch_state,
    write_back_ifc.in i_alu_write_back, 
    write_back_ifc.in i_load_write_back, 

	memory_issue_queue_ifc.out next_mem_queue,
    integer_issue_queue_ifc.out next_int_queue,
	branch_state_ifc.out next_branch_state,
    
    output logic issue_queue_full

); 

	logic [`INT_QUEUE_SIZE_INDEX - 1 : 0] int_queue_insert_index [`ISSUE_SIZE];
    logic [`MEM_QUEUE_SIZE_INDEX - 1 : 0] mem_queue_insert_index; 
 
    logic [`INT_QUEUE_SIZE_INDEX - 1 : 0] int_queue_insert_index_1; 
    logic [`INT_QUEUE_SIZE_INDEX - 1 : 0] int_queue_insert_index_2; 


	priority_encoder# (
		.m(`INT_QUEUE_SIZE),
		.n(`INT_QUEUE_SIZE_INDEX)
	) int_queue_insert_index_retriever_1 (
		.x(curr_int_queue.entry_available_bit),
		.bottom_up(1'b1),
		.valid_in(),
		.y(int_queue_insert_index_1)
	);

	priority_encoder# (
		.m(`INT_QUEUE_SIZE),
		.n(`INT_QUEUE_SIZE_INDEX)
	) int_queue_insert_index_retriever_2 (
		.x(curr_int_queue.entry_available_bit),
		.bottom_up(1'b0),
		.valid_in(),
		.y(int_queue_insert_index_2)
	);


    priority_encoder# (
		.m(`MEM_QUEUE_SIZE),
		.n(`MEM_QUEUE_SIZE_INDEX)
    ) mem_queue_insert_index_retriever (
		.x(curr_mem_queue.entry_available_bit),
		.bottom_up(1'b1),
		.valid_in(),
		.y(mem_queue_insert_index)
	);

	always_comb 
    begin

        issue_queue_full = 1'b0; 
        int_queue_insert_index[0] = int_queue_insert_index_1; 
        int_queue_insert_index[1] = int_queue_insert_index_2; 

        if (issue_in.valid[0] && issue_in.is_branch[0])
        begin
            if (curr_int_queue.entry_available_bit == '0)
			    issue_queue_full = 1'b1; 
            else if (issue_in.valid[1])
            begin
                if (issue_in.is_mem_access[1] && curr_mem_queue.entry_available_bit == '0)
                    issue_queue_full = 1'b1; 
                else if (int_queue_insert_index_1 == int_queue_insert_index_2)
                    issue_queue_full = 1'b1; 
            end
        end
        else if (issue_in.valid[0])
        begin
            if (issue_in.is_mem_access[1] && curr_mem_queue.entry_available_bit == '0)
                issue_queue_full = 1'b1; 
            else if (curr_int_queue.entry_available_bit == '0)
                issue_queue_full = 1'b1;
        end
    end

    always_comb
    begin
        if (!rst_n)
        begin

            for (int i = 0; i < `BRANCH_NUM; i++)
			begin
				next_branch_state.rename_buffer[i] = '{default: 0}; 
			end

			next_branch_state.write_pointer = '0; 
			next_branch_state.valid = '0; 
			next_branch_state.free_head_pointer = '{default: 0}; 
			next_branch_state.branch_id = '{default: 0}; 
            next_branch_state.ds_valid = '{default: 0};

            next_int_queue.entry_available_bit = {(`INT_QUEUE_SIZE){1'b1}}; 
            next_int_queue.src1 = '{default: 0};
            next_int_queue.ready_bit_src1 = '{default: 0}; 
            next_int_queue.src2 = '{default: 0};
            next_int_queue.ready_bit_src2 = '{default: 0};
            next_int_queue.immediate_data = '{default: 0}; 
            next_int_queue.alu_ctl = '{default: ALUCTL_NOP}; 
            next_int_queue.is_branch = '{default: 0}; 
            next_int_queue.prediction = '{default: TAKEN};
            next_int_queue.recovery_target ='{default: 0}; 
            next_int_queue.uses_rs = '{default: 0};
            next_int_queue.uses_rt = '{default: 0};
            next_int_queue.uses_immediate = '{default: 0};
            next_int_queue.active_list_id = '{default: 0};

            next_mem_queue.entry_available_bit = {(`MEM_QUEUE_SIZE){1'b1}}; 
            next_mem_queue.src1 = '{default: 0}; 
            next_mem_queue.ready_bit_src1 = '{default: 0};
            next_mem_queue.sw_src = '{default: 0};
            next_mem_queue.ready_bit_sw_src = '{default: 0};
            next_mem_queue.immediate_data = '{default: 0}; 
            next_mem_queue.mem_action = '{default: READ};
            next_mem_queue.uses_rs = '{default: 0};
            next_mem_queue.active_list_id = '{default: 0};
        end
        else 
        begin
			next_branch_state.write_pointer = curr_branch_state.write_pointer; 
			next_branch_state.valid = curr_branch_state.valid; 
			next_branch_state.free_head_pointer = curr_branch_state.free_head_pointer; 
			next_branch_state.rename_buffer = curr_branch_state.rename_buffer; 
			next_branch_state.branch_id = curr_branch_state.branch_id; 
            next_branch_state.ds_valid = curr_branch_state.ds_valid; 

            next_int_queue.entry_available_bit = curr_int_queue.entry_available_bit; 
            next_int_queue.src1 = curr_int_queue.src1; 
            next_int_queue.ready_bit_src1 = curr_int_queue.ready_bit_src1; 
            next_int_queue.src2 = curr_int_queue.src2;
            next_int_queue.ready_bit_src2 = curr_int_queue.ready_bit_src2; 
            next_int_queue.immediate_data = curr_int_queue.immediate_data; 
            next_int_queue.alu_ctl = curr_int_queue.alu_ctl; 
            next_int_queue.is_branch = curr_int_queue.is_branch; 
            next_int_queue.prediction = curr_int_queue.prediction; 
            next_int_queue.recovery_target = curr_int_queue.recovery_target; 
            next_int_queue.uses_rs = curr_int_queue.uses_rs; 
            next_int_queue.uses_rt = curr_int_queue.uses_rt;
            next_int_queue.uses_immediate = curr_int_queue.uses_immediate;
            next_int_queue.active_list_id = curr_int_queue.active_list_id; 

            next_mem_queue.entry_available_bit = curr_mem_queue.entry_available_bit; 
            next_mem_queue.src1 = curr_mem_queue.src1; 
            next_mem_queue.ready_bit_src1 = curr_mem_queue.ready_bit_src1; 
            next_mem_queue.sw_src = curr_mem_queue.sw_src; 
            next_mem_queue.ready_bit_sw_src = curr_mem_queue.ready_bit_sw_src; 
            next_mem_queue.immediate_data = curr_mem_queue.immediate_data; 
            next_mem_queue.mem_action = curr_mem_queue.mem_action; 
            next_mem_queue.uses_rs = curr_mem_queue.uses_rs;
            next_mem_queue.active_list_id = curr_mem_queue.active_list_id; 
        end


		if (!issue_queue_full)
        begin
            for (int i = 0; i < `ISSUE_SIZE; i++)
            begin
                if (issue_in.valid[i])
                begin
                    if (issue_in.is_mem_access[i])
                    begin 
                        next_mem_queue.entry_available_bit[mem_queue_insert_index] = 1'b0; 
                        next_mem_queue.src1[mem_queue_insert_index] = issue_in.phys_rs[i]; 
                        next_mem_queue.ready_bit_src1[mem_queue_insert_index] = issue_in.uses_rs[i] ? issue_in.phys_rs_valid[i] : 1'b1; 
                        next_mem_queue.immediate_data[mem_queue_insert_index] = issue_in.immediate[i]; 
                        next_mem_queue.sw_src[mem_queue_insert_index] = issue_in.phys_rt[i]; 
                        next_mem_queue.ready_bit_sw_src[mem_queue_insert_index] = issue_in.uses_rt[i] ? issue_in.phys_rt_valid[i] : 1'b1; 
                        next_mem_queue.mem_action[mem_queue_insert_index] = issue_in.mem_action[i]; 
                        next_mem_queue.uses_rs[mem_queue_insert_index] = issue_in.uses_rs[i];	
                        next_mem_queue.active_list_id[mem_queue_insert_index] = issue_in.active_list_id[i]; 
                    end
                    else
                    begin
                        next_int_queue.entry_available_bit[int_queue_insert_index[i]] = 1'b0; 
                        next_int_queue.src1[int_queue_insert_index[i]] = issue_in.phys_rs[i]; 
                        next_int_queue.ready_bit_src1[int_queue_insert_index[i]] = issue_in.uses_rs[i] ? issue_in.phys_rs_valid[i] : 1'b1; 
                        next_int_queue.src2[int_queue_insert_index[i]] = issue_in.phys_rt[i]; 
                        next_int_queue.ready_bit_src2[int_queue_insert_index[i]] = issue_in.uses_rt[i] ? issue_in.phys_rt_valid[i] : 1'b1;
                        next_int_queue.immediate_data[int_queue_insert_index[i]] = issue_in.uses_immediate[i] ? issue_in.immediate[i] : 0; 
                        next_int_queue.alu_ctl[int_queue_insert_index[i]] = issue_in.alu_ctl[i]; 
                        next_int_queue.is_branch[int_queue_insert_index[i]] = issue_in.is_branch[i]; 
                        next_int_queue.prediction[int_queue_insert_index[i]] = issue_in.prediction[i];
                        next_int_queue.recovery_target[int_queue_insert_index[i]] = issue_in.recovery_target[i];
                        next_int_queue.uses_rs[int_queue_insert_index[i]] = issue_in.uses_rs[i]; 
                        next_int_queue.uses_rt[int_queue_insert_index[i]] = issue_in.uses_rt[i];
                        next_int_queue.uses_immediate[int_queue_insert_index[i]] = issue_in.uses_immediate[i]; 
                        next_int_queue.active_list_id[int_queue_insert_index[i]] = issue_in.active_list_id[i]; 
                    end
                end
            end

            if (issue_in.valid[0] && issue_in.is_branch[0])
            begin
				next_branch_state.valid[curr_branch_state.write_pointer] = 1'b1; 
                next_branch_state.free_head_pointer[curr_branch_state.write_pointer] = curr_rename_state.free_head_pointer; 
                next_branch_state.rename_buffer[curr_branch_state.write_pointer] = curr_rename_state.rename_buffer;
                next_branch_state.branch_id[curr_branch_state.write_pointer] = issue_in.active_list_id[0]; 
                next_branch_state.ds_valid[curr_branch_state.write_pointer] = issue_in.valid[1]; 
                next_branch_state.write_pointer = curr_branch_state.write_pointer + 1'b1; 	
            end

        end

		for (int i = 0; i < `INT_QUEUE_SIZE; i++) 
		begin
			if (i_alu_write_back.valid && i_alu_write_back.uses_rw && i_alu_write_back.rw_addr == next_int_queue.src1[i] && next_int_queue.entry_available_bit[i] == 0) 
				next_int_queue.ready_bit_src1[i] = 1'b1; 
			if (i_alu_write_back.valid && i_alu_write_back.uses_rw && i_alu_write_back.rw_addr == next_int_queue.src2[i] && next_int_queue.entry_available_bit[i] == 0) 
				next_int_queue.ready_bit_src2[i] = 1'b1; 	
			if (i_load_write_back.valid && i_load_write_back.uses_rw && i_load_write_back.rw_addr == next_int_queue.src1[i] && next_int_queue.entry_available_bit[i] == 0)
				next_int_queue.ready_bit_src1[i] = 1'b1;
			if (i_load_write_back.valid && i_load_write_back.uses_rw && i_load_write_back.rw_addr == next_int_queue.src2[i] && next_int_queue.entry_available_bit[i] == 0) 
				next_int_queue.ready_bit_src2[i] = 1'b1; 
		end

		for (int i = 0; i < `MEM_QUEUE_SIZE; i++) 
		begin
			if (i_alu_write_back.valid && i_alu_write_back.rw_addr == next_mem_queue.src1[i] && next_mem_queue.entry_available_bit[i] == 0) 
				next_mem_queue.ready_bit_src1[i] = 1'b1; 
			if (i_alu_write_back.valid && i_alu_write_back.rw_addr == next_mem_queue.sw_src[i] && next_mem_queue.entry_available_bit[i] == 0) 
				next_mem_queue.ready_bit_sw_src[i] = 1'b1; 	
			if (i_load_write_back.valid && i_load_write_back.rw_addr == next_mem_queue.src1[i] && next_mem_queue.entry_available_bit[i] == 0) 
				next_mem_queue.ready_bit_src1[i] = 1'b1; 
			if (i_load_write_back.valid && i_load_write_back.rw_addr == next_mem_queue.sw_src[i] && next_mem_queue.entry_available_bit[i] == 0) 
				next_mem_queue.ready_bit_sw_src[i] = 1'b1; 
		end



	end

endmodule