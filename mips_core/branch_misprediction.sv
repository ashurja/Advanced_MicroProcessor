
interface branch_state_ifc (); 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id [`BRANCH_NUM]; 
    logic [`BRANCH_NUM - 1 : 0] valid; 
    logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_head_pointer [`BRANCH_NUM]; 
    logic [`PHYS_REG_NUM_INDEX - 1 : 0] rename_buffer [`BRANCH_NUM] [`REG_NUM]; 
    logic [`BRANCH_NUM_INDEX - 1 : 0] write_pointer;
    logic ds_valid [`BRANCH_NUM]; 

	modport in (input valid, free_head_pointer, rename_buffer, write_pointer, branch_id, ds_valid);
	modport out (output valid, free_head_pointer, rename_buffer, write_pointer, branch_id, ds_valid);
endinterface


module branch_misprediction  (
    input rst_n,

    hazard_signals_ifc.in hazard_signal_in,

    branch_state_ifc.in curr_branch_state,
    rename_ifc.in curr_rename_state, 
    active_state_ifc.in curr_active_state,
    integer_issue_queue_ifc.in curr_int_queue,
    memory_issue_queue_ifc.in curr_mem_queue, 
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
    commit_state_ifc.in curr_commit_state, 
    global_controls_ifc.in curr_global_controls, 

    rename_ifc.out misprediction_rename_state, 
    active_state_ifc.out misprediction_active_state, 
    integer_issue_queue_ifc.out misprediction_int_queue,
    memory_issue_queue_ifc.out misprediction_mem_queue, 
    load_queue_ifc.out misprediction_load_queue, 
    store_queue_ifc.out misprediction_store_queue,
    branch_state_ifc.out misprediction_branch_state, 
    commit_state_ifc.out misprediction_commit_state, 
    global_controls_ifc.out misprediction_global_controls
);
    
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id_with_ds; 
    logic color_bit_with_ds; 

    logic [`BRANCH_NUM - 1 : 0] cmpt_misprediction_idx; 
    logic [`BRANCH_NUM_INDEX - 1 : 0] misprediction_idx; 

	priority_encoder# (
		.m(`BRANCH_NUM),
		.n(`BRANCH_NUM_INDEX)
    ) misprediction_idx_retriever (
		.x(cmpt_misprediction_idx),
		.bottom_up(1'b1),
		.valid_in(),
		.y(misprediction_idx)
	);


    always_comb
    begin : handle_misprediction
        misprediction_branch_state.write_pointer = curr_branch_state.write_pointer; 
        misprediction_branch_state.valid = curr_branch_state.valid; 

        cmpt_misprediction_idx = '0;
        if (hazard_signal_in.branch_miss)
        begin

            for (int i = 0; i < `BRANCH_NUM; i++)
            begin
                if (curr_branch_state.valid[i] && curr_branch_state.branch_id[i] == hazard_signal_in.branch_id)
                begin
                    cmpt_misprediction_idx[i] = 1'b1; 
                end
            end

            misprediction_branch_state.write_pointer = misprediction_idx; 

            for (int i = 0; i < `BRANCH_NUM; i++)
            begin
                if (curr_active_state.color_bit[curr_branch_state.branch_id[i]] == hazard_signal_in.color_bit)
                begin
                    if (curr_branch_state.branch_id[i] >= hazard_signal_in.branch_id)
                        misprediction_branch_state.valid[i] = 1'b0; 
                end

                else
                begin
                    if (curr_branch_state.branch_id[i] <= hazard_signal_in.branch_id)
                        misprediction_branch_state.valid[i] = 1'b0; 
                end
            end
        end
    end


    always_comb
    begin
        branch_id_with_ds = '0; 
        color_bit_with_ds = 1'b0; 

        if (curr_branch_state.ds_valid[misprediction_idx])
        begin
            branch_id_with_ds = hazard_signal_in.branch_id + 1'b1; 
            color_bit_with_ds = (branch_id_with_ds == 0) ? !hazard_signal_in.color_bit : hazard_signal_in.color_bit; 
        end
        else 
        begin
            branch_id_with_ds = hazard_signal_in.branch_id; 
            color_bit_with_ds = hazard_signal_in.color_bit; 
        end

    end

    always_comb
    begin : handle_rename_state
 
        misprediction_rename_state.free_head_pointer = curr_rename_state.free_head_pointer; 
        misprediction_rename_state.rename_buffer = curr_rename_state.rename_buffer; 

        if (hazard_signal_in.branch_miss)
        begin
            misprediction_rename_state.free_head_pointer = curr_branch_state.free_head_pointer[misprediction_idx]; 
            misprediction_rename_state.rename_buffer = curr_branch_state.rename_buffer[misprediction_idx]; 
        end
    end


    always_comb
    begin : handle_active_state
 
        misprediction_active_state.youngest_inst_pointer = curr_active_state.youngest_inst_pointer; 
        misprediction_active_state.global_color_bit = curr_active_state.global_color_bit; 


        if (hazard_signal_in.branch_miss)
        begin
            misprediction_active_state.youngest_inst_pointer = branch_id_with_ds + 1'b1; 
            misprediction_active_state.global_color_bit = color_bit_with_ds; 
        end
    end





    always_comb
    begin : handle_issue_queues

        misprediction_int_queue.entry_available_bit = curr_int_queue.entry_available_bit; 

        misprediction_mem_queue.entry_available_bit = curr_mem_queue.entry_available_bit;  

        if (hazard_signal_in.branch_miss)
        begin
            
            for (int i = 0; i < `INT_QUEUE_SIZE; i++)
            begin
                if (color_bit_with_ds == curr_active_state.color_bit[curr_int_queue.active_list_id[i]])
                begin
                    if (branch_id_with_ds < curr_int_queue.active_list_id[i])
                        misprediction_int_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (branch_id_with_ds > curr_int_queue.active_list_id[i])
                        misprediction_int_queue.entry_available_bit[i] = 1'b1; 
                end
            end


            for (int i = 0; i < `MEM_QUEUE_SIZE; i++)
            begin
                if (color_bit_with_ds == curr_active_state.color_bit[curr_mem_queue.active_list_id[i]])
                begin
                    if (branch_id_with_ds < curr_mem_queue.active_list_id[i])
                        misprediction_mem_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (branch_id_with_ds > curr_mem_queue.active_list_id[i])
                        misprediction_mem_queue.entry_available_bit[i] = 1'b1; 
                end
            end
        end
    end


    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_queue_traverse_pointer; 
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_load_write_pointer; 

    logic load_queue_branch_dependant; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] new_load_write_pointer; 


    logic [`LOAD_STORE_SIZE_INDEX -  1 : 0] store_queue_traverse_pointer; 
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_store_write_pointer; 

    logic store_queue_branch_dependant; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] new_store_write_pointer; 

	priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) load_write_pointer_retriever (
		.x(cmpt_load_write_pointer),
		.bottom_up(1'b1),
		.valid_in(load_queue_branch_dependant),
		.y(new_load_write_pointer)
	);


	priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) store_write_pointer_retriever (
		.x(cmpt_store_write_pointer),
		.bottom_up(1'b1),
		.valid_in(store_queue_branch_dependant),
		.y(new_store_write_pointer)
	);

    always_comb
    begin : handle_d_cache_input_queues
        misprediction_load_queue.entry_available_bit = curr_load_queue.entry_available_bit; 
        misprediction_load_queue.active_list_id = curr_load_queue.active_list_id; 
        misprediction_load_queue.read_pointer = curr_load_queue.read_pointer; 
        misprediction_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer; 


        misprediction_store_queue.active_list_id = curr_store_queue.active_list_id; 
        misprediction_store_queue.entry_available_bit = curr_store_queue.entry_available_bit; 
        misprediction_store_queue.read_pointer = curr_store_queue.read_pointer; 
        misprediction_store_queue.entry_write_pointer = curr_store_queue.entry_write_pointer; 


        misprediction_global_controls.invalidate_d_cache_output = curr_global_controls.invalidate_d_cache_output; 

        load_queue_traverse_pointer = '0; 
        store_queue_traverse_pointer = '0; 

        cmpt_load_write_pointer = '0; 
        cmpt_store_write_pointer = '0; 
 
        if (hazard_signal_in.branch_miss)
        begin
            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                if (color_bit_with_ds == curr_active_state.color_bit[curr_load_queue.active_list_id[i]])
                begin
                    if (branch_id_with_ds < curr_load_queue.active_list_id[i])
                        misprediction_load_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (branch_id_with_ds > curr_load_queue.active_list_id[i])
                        misprediction_load_queue.entry_available_bit[i] = 1'b1; 
                end
            end


            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                if (color_bit_with_ds == curr_active_state.color_bit[curr_store_queue.active_list_id[i]])
                begin
                    if (branch_id_with_ds < curr_store_queue.active_list_id[i])
                        misprediction_store_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (branch_id_with_ds > curr_store_queue.active_list_id[i])
                        misprediction_store_queue.entry_available_bit[i] = 1'b1; 
                end
            end

            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                load_queue_traverse_pointer = (curr_load_queue.read_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]); 
                if (misprediction_load_queue.entry_available_bit[load_queue_traverse_pointer])
                    cmpt_load_write_pointer[i] = 1'b1; 
            end

            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                store_queue_traverse_pointer = (curr_store_queue.read_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]); 
                if (misprediction_store_queue.entry_available_bit[store_queue_traverse_pointer])
                    cmpt_store_write_pointer[i] = 1'b1; 
            end

            if (load_queue_branch_dependant)
                misprediction_load_queue.entry_write_pointer = new_load_write_pointer + curr_load_queue.read_pointer; 

            if (store_queue_branch_dependant)
                misprediction_store_queue.entry_write_pointer = new_store_write_pointer + curr_store_queue.read_pointer; 

            if (hazard_signal_in.dc_miss) 
            begin
                if (misprediction_store_queue.entry_available_bit[curr_store_queue.read_pointer] ||
                    misprediction_load_queue.entry_available_bit[curr_load_queue.read_pointer])
                        misprediction_global_controls.invalidate_d_cache_output = 1'b1; 
            end
        end
    end


    always_comb
    begin
        misprediction_commit_state.ready_to_commit = curr_commit_state.ready_to_commit; 
        misprediction_commit_state.entry_available_bit = curr_commit_state.entry_available_bit; 

        if (hazard_signal_in.branch_miss)
        begin
            for (int i = 0; i < `ACTIVE_LIST_SIZE; i++)
            begin
                if (color_bit_with_ds == curr_active_state.color_bit[i])
                begin
                    if (branch_id_with_ds < i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0])
                    begin
                        misprediction_commit_state.ready_to_commit[i] = 1'b0; 
                        misprediction_commit_state.entry_available_bit[i] = 1'b1; 
                    end

                end
                else 
                begin
                    if (branch_id_with_ds > i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0])
                    begin
                        misprediction_commit_state.ready_to_commit[i] = 1'b0; 
                        misprediction_commit_state.entry_available_bit[i] = 1'b1; 
                    end
                end
            end
        end
    end

endmodule