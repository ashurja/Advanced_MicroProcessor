
interface branch_state_ifc (); 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id [`BRANCH_NUM]; 
    logic [`BRANCH_NUM - 1 : 0] valid; 
    logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_head_pointer [`BRANCH_NUM]; 

    logic [`PHYS_REG_NUM_INDEX - 1 : 0] rename_buffer [`BRANCH_NUM] [`REG_NUM]; 
    logic [`BRANCH_NUM_INDEX - 1 : 0] write_pointer;
    logic ds_valid [`BRANCH_NUM]; 

    logic [`GHR_LEN - 1 : 0] GHR [`BRANCH_NUM]; 

	logic [$clog2(`TAGE_TABLE_LEN) - 1 : 0] CSR_IDX [`BRANCH_NUM][`TAGE_TABLE_NUM - 1];
	logic [`TAGE_TAG_WIDTH - 1 : 0] CSR_TAG [`BRANCH_NUM][`TAGE_TABLE_NUM - 1];
	logic [`TAGE_TAG_WIDTH - 2 : 0] CSR_TAG_2 [`BRANCH_NUM][`TAGE_TABLE_NUM - 1];

	modport in (input valid, free_head_pointer, rename_buffer, GHR, write_pointer, branch_id, ds_valid, CSR_IDX, CSR_TAG, CSR_TAG_2); 
	modport out (output valid, free_head_pointer, rename_buffer, GHR, write_pointer, branch_id, ds_valid, CSR_IDX, CSR_TAG, CSR_TAG_2); 
endinterface

interface misprediction_output_ifc (); 
    logic invalidate_d_cache_output; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] branch_id_with_ds; 
    logic color_bit_with_ds; 

    modport in (input invalidate_d_cache_output, branch_id_with_ds, color_bit_with_ds); 
    modport out (output invalidate_d_cache_output, branch_id_with_ds, color_bit_with_ds); 
endinterface

module branch_misprediction (
    input rst_n,

    hazard_signals_ifc.in hazard_signal_in,

    d_cache_controls_ifc.in o_d_cache_controls,

    branch_state_ifc.in curr_branch_state,
    rename_ifc.in curr_rename_state, 
    active_state_ifc.in curr_active_state,
    integer_issue_queue_ifc.in curr_int_queue,
    memory_issue_queue_ifc.in curr_mem_queue, 
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
    commit_state_ifc.in curr_commit_state, 
    branch_controls_ifc.in curr_branch_controls,

    rename_ifc.out misprediction_rename_state, 
    active_state_ifc.out misprediction_active_state, 
    integer_issue_queue_ifc.out misprediction_int_queue,
    memory_issue_queue_ifc.out misprediction_mem_queue, 
    load_queue_ifc.out misprediction_load_queue, 
    store_queue_ifc.out misprediction_store_queue,
    branch_state_ifc.out misprediction_branch_state, 
    branch_controls_ifc.out misprediction_branch_controls,
    misprediction_output_ifc.out misprediction_out
);

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

            misprediction_branch_state.write_pointer = misprediction_idx + 1'b1; 

            for (int i = 0; i < `BRANCH_NUM; i++)
            begin
                if (curr_active_state.color_bit[curr_branch_state.branch_id[i]] == hazard_signal_in.color_bit)
                begin
                    if (hazard_signal_in.branch_id < curr_branch_state.branch_id[i])
                        misprediction_branch_state.valid[i] = 1'b0; 
                end

                else
                begin
                    if (hazard_signal_in.branch_id > curr_branch_state.branch_id[i])
                        misprediction_branch_state.valid[i] = 1'b0; 
                end
            end
        end
    end


    always_comb
    begin

        if (curr_branch_state.ds_valid[misprediction_idx])
        begin
           misprediction_out.branch_id_with_ds = hazard_signal_in.branch_id + 1'b1; 
           misprediction_out.color_bit_with_ds = (misprediction_out.branch_id_with_ds == 0) ? !hazard_signal_in.color_bit : hazard_signal_in.color_bit; 
        end
        else 
        begin
           misprediction_out.branch_id_with_ds = hazard_signal_in.branch_id; 
           misprediction_out.color_bit_with_ds = hazard_signal_in.color_bit; 
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
            misprediction_active_state.youngest_inst_pointer = misprediction_out.branch_id_with_ds + 1'b1; 
            misprediction_active_state.global_color_bit = (misprediction_out.branch_id_with_ds == `ACTIVE_LIST_SIZE - 1'b1) ? !misprediction_out.color_bit_with_ds : misprediction_out.color_bit_with_ds; 
        end
    end

    logic [`BRANCH_NUM_INDEX - 1 : 0] tage_feed_idx; 
    always_comb
    begin : handle_branch_controls
        tage_feed_idx = '0; 
        misprediction_branch_controls.GHR = curr_branch_controls.GHR; 

        misprediction_branch_controls.CSR_IDX = curr_branch_controls.CSR_IDX; 
        misprediction_branch_controls.CSR_TAG = curr_branch_controls.CSR_TAG; 
        misprediction_branch_controls.CSR_TAG_2 = curr_branch_controls.CSR_TAG_2; 

        misprediction_branch_controls.CSR_IDX_FEED = curr_branch_controls.CSR_IDX_FEED; 
        misprediction_branch_controls.CSR_TAG_FEED = curr_branch_controls.CSR_TAG_FEED; 
        misprediction_branch_controls.CSR_TAG_2_FEED = curr_branch_controls.CSR_TAG_2_FEED; 

        if (hazard_signal_in.branch_miss)
        begin

            if (misprediction_idx == 0) 
                tage_feed_idx = `BRANCH_NUM - 1; 
            else 
                tage_feed_idx = misprediction_idx - 1; 

            for (int i = 0; i < `TAGE_TABLE_NUM - 1; i++) begin 
                misprediction_branch_controls.CSR_IDX[i] = {curr_branch_state.CSR_IDX[misprediction_idx][i][$clog2(`TAGE_TABLE_LEN) - 1 : 1], !curr_branch_state.CSR_IDX[misprediction_idx][i][0]}; 
                misprediction_branch_controls.CSR_TAG[i] = {curr_branch_state.CSR_TAG[misprediction_idx][i][`TAGE_TAG_WIDTH - 1 : 1], !curr_branch_state.CSR_TAG[misprediction_idx][i][0]};  
                misprediction_branch_controls.CSR_TAG_2[i] = {curr_branch_state.CSR_TAG_2[misprediction_idx][i][`TAGE_TAG_WIDTH - 2 : 1], !curr_branch_state.CSR_TAG_2[misprediction_idx][i][0]};

                misprediction_branch_controls.CSR_IDX_FEED[i] = curr_branch_state.CSR_IDX[tage_feed_idx][i]; 
                misprediction_branch_controls.CSR_TAG_FEED[i] = curr_branch_state.CSR_TAG[tage_feed_idx][i];  
                misprediction_branch_controls.CSR_TAG_2_FEED[i] = curr_branch_state.CSR_TAG_2[tage_feed_idx][i];
            end

            misprediction_branch_controls.GHR = {curr_branch_state.GHR[misprediction_idx][`GHR_LEN - 1 : 1], !curr_branch_state.GHR[misprediction_idx][0]}; 
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
                if (misprediction_out.color_bit_with_ds == curr_active_state.color_bit[curr_int_queue.active_list_id[i]])
                begin
                    if (misprediction_out.branch_id_with_ds < curr_int_queue.active_list_id[i])
                        misprediction_int_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (misprediction_out.branch_id_with_ds > curr_int_queue.active_list_id[i])
                        misprediction_int_queue.entry_available_bit[i] = 1'b1; 
                end
            end


            for (int i = 0; i < `MEM_QUEUE_SIZE; i++)
            begin
                if (misprediction_out.color_bit_with_ds == curr_active_state.color_bit[curr_mem_queue.active_list_id[i]])
                begin
                    if (misprediction_out.branch_id_with_ds < curr_mem_queue.active_list_id[i])
                        misprediction_mem_queue.entry_available_bit[i] = 1'b1; 
                end
                else 
                begin
                    if (misprediction_out.branch_id_with_ds > curr_mem_queue.active_list_id[i])
                        misprediction_mem_queue.entry_available_bit[i] = 1'b1; 
                end
            end
        end
    end

    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_queue_traverse_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX -  1 : 0] store_queue_traverse_pointer; 

    logic load_write_found; 
    logic store_write_found; 

    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_store_write_pointer; 
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_load_write_pointer; 

    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] new_load_write_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] new_store_write_pointer; 
    

	priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) load_write_pointer_retriever (
		.x(cmpt_load_write_pointer),
		.bottom_up(1'b1),
		.valid_in(load_write_found),
		.y(new_load_write_pointer)
	);


	priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) store_write_pointer_retriever (
		.x(cmpt_store_write_pointer),
		.bottom_up(1'b1),
		.valid_in(store_write_found),
		.y(new_store_write_pointer)
	);

    always_comb
    begin : handle_d_cache_input_queues
        misprediction_out.invalidate_d_cache_output = 1'b0; 

        misprediction_load_queue.entry_available_bit = curr_load_queue.entry_available_bit; 
        misprediction_load_queue.active_list_id = curr_load_queue.active_list_id; 
        misprediction_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer; 
        misprediction_load_queue.valid = curr_load_queue.valid; 

        misprediction_store_queue.active_list_id = curr_store_queue.active_list_id; 
        misprediction_store_queue.entry_available_bit = curr_store_queue.entry_available_bit; 
        misprediction_store_queue.read_pointer = curr_store_queue.read_pointer; 
        misprediction_store_queue.entry_write_pointer = curr_store_queue.entry_write_pointer; 
        misprediction_store_queue.valid = curr_store_queue.valid; 

        load_queue_traverse_pointer = '0; 
        store_queue_traverse_pointer = '0; 

        cmpt_load_write_pointer = '0; 
        cmpt_store_write_pointer = '0; 
 
        if (hazard_signal_in.branch_miss)
        begin
            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                if (misprediction_out.color_bit_with_ds == curr_active_state.color_bit[curr_load_queue.active_list_id[i]])
                begin
                    if (misprediction_out.branch_id_with_ds < curr_load_queue.active_list_id[i])
                    begin
                        misprediction_load_queue.entry_available_bit[i] = 1'b1;    
                        misprediction_load_queue.valid[i] = 1'b0;  
                    end
                        
                end
                else 
                begin
                    if (misprediction_out.branch_id_with_ds > curr_load_queue.active_list_id[i])
                    begin
                        misprediction_load_queue.entry_available_bit[i] = 1'b1;    
                        misprediction_load_queue.valid[i] = 1'b0;  
                    end
                        
                end
            end


            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                if (misprediction_out.color_bit_with_ds == curr_active_state.color_bit[curr_store_queue.active_list_id[i]])
                begin
                    if (misprediction_out.branch_id_with_ds < curr_store_queue.active_list_id[i])
                    begin
                        misprediction_store_queue.entry_available_bit[i] = 1'b1;    
                        misprediction_store_queue.valid[i] = 1'b0;  
                    end
                end
                else 
                begin
                    if (misprediction_out.branch_id_with_ds > curr_store_queue.active_list_id[i])
                    begin
                        misprediction_store_queue.entry_available_bit[i] = 1'b1;    
                        misprediction_store_queue.valid[i] = 1'b0;  
                    end
                end
            end

            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                load_queue_traverse_pointer = (curr_commit_state.load_commit_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]); 
                if (misprediction_load_queue.entry_available_bit[load_queue_traverse_pointer])
                    cmpt_load_write_pointer[i] = 1'b1; 
            end

            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                store_queue_traverse_pointer = (curr_commit_state.store_commit_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]); 
                if (misprediction_store_queue.entry_available_bit[store_queue_traverse_pointer])
                    cmpt_store_write_pointer[i] = 1'b1; 
            end


            if (load_write_found) misprediction_load_queue.entry_write_pointer = new_load_write_pointer + curr_commit_state.load_commit_pointer; 
            if (store_write_found) misprediction_store_queue.entry_write_pointer = new_store_write_pointer + curr_commit_state.store_commit_pointer; 

            if (hazard_signal_in.dc_miss) 
            begin
                if(o_d_cache_controls.mem_action == READ)
                begin
                    misprediction_out.invalidate_d_cache_output = misprediction_load_queue.entry_available_bit[o_d_cache_controls.dispatch_index]; 
                end
            end
        end
    end

endmodule