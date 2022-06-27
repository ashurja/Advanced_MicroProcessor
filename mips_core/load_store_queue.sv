interface load_queue_ifc();
    logic [`LOAD_STORE_SIZE - 1 : 0] entry_available_bit; 
    logic [`LOAD_STORE_SIZE - 1 : 0] valid; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] entry_write_pointer; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`LOAD_STORE_SIZE]; 
    logic [`ADDR_WIDTH - 1 : 0] mem_addr[`LOAD_STORE_SIZE]; 

    modport in (input valid, mem_addr, entry_available_bit, entry_write_pointer,
            active_list_id);
    modport out (output valid, mem_addr, entry_available_bit, entry_write_pointer,
            active_list_id);
endinterface //load_queue_ifc


interface store_queue_ifc(); 
	logic [`LOAD_STORE_SIZE - 1 : 0] valid;  
    logic [`LOAD_STORE_SIZE - 1 : 0] entry_available_bit; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] read_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] entry_write_pointer; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`LOAD_STORE_SIZE]; 

    logic [`ADDR_WIDTH - 1 : 0] mem_addr[`LOAD_STORE_SIZE]; 
    logic [`DATA_WIDTH - 1 : 0] sw_data [`LOAD_STORE_SIZE];  

    modport in (input valid, mem_addr, sw_data, entry_available_bit, read_pointer, entry_write_pointer, 
        active_list_id); 
    modport out (output valid, mem_addr, sw_data, entry_available_bit, read_pointer, entry_write_pointer, 
        active_list_id); 
endinterface

module load_store_queue (
    input rst_n,
    
    hazard_signals_ifc.in hazard_signal_in, 
    scheduler_output_ifc.in i_scheduler,
    commit_state_ifc.in curr_commit_state, 
    reg_file_output_ifc.in i_reg_data, 
    agu_output_ifc.in i_agu_output,
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
    load_queue_ifc.in misprediction_load_queue, 
    store_queue_ifc.in misprediction_store_queue, 
    active_state_ifc.in curr_active_state, 
    memory_issue_queue_ifc.in curr_mem_queue, 
    commit_output_ifc.in i_commit_out, 
    rename_ifc.in curr_rename_state, 
    
    load_queue_ifc.out next_load_queue, 
    store_queue_ifc.out next_store_queue,
    d_cache_controls_ifc.out o_d_cache_controls, 
    d_cache_input_ifc.out o_d_cache_input, 

    output load_store_queue_full
);

    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_entry; 
    logic [`LOAD_STORE_SIZE_INDEX  - 1 : 0] cmpt_entry_index; 
    
    priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) new_entry_retriever (
		.x(cmpt_entry),
		.bottom_up(1'b1),
		.valid_in(),
		.y(cmpt_entry_index)
	);


    always_comb
    begin
        load_store_queue_full = 1'b0; 
        if (curr_load_queue.entry_available_bit == '0 || curr_store_queue.entry_available_bit == '0)
            load_store_queue_full = 1'b1; 
    end

    always_comb
    begin
        cmpt_entry = '0; 
        if (!rst_n)
        begin
            next_load_queue.valid = '0; 
            next_load_queue.mem_addr = '{default: 0}; 
            next_load_queue.entry_available_bit = {(`LOAD_STORE_SIZE){1'b1}}; 
            next_load_queue.active_list_id = '{default: 0}; 
            next_load_queue.entry_write_pointer = '0; 

            next_store_queue.valid = '0; 
            next_store_queue.sw_data = '{default: 0}; 
            next_store_queue.mem_addr = '{default: 0}; 
            next_store_queue.entry_available_bit = {(`LOAD_STORE_SIZE){1'b1}}; 
            next_store_queue.active_list_id = '{default: 0}; 
            next_store_queue.read_pointer = '0; 
            next_store_queue.entry_write_pointer = '0; 
        end
        else 
        begin
            next_load_queue.valid = misprediction_load_queue.valid; 
            next_load_queue.mem_addr = curr_load_queue.mem_addr; 
            next_load_queue.active_list_id = curr_load_queue.active_list_id; 
            next_load_queue.entry_available_bit = curr_load_queue.entry_available_bit; 
            next_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer; 

            next_store_queue.valid = misprediction_store_queue.valid; 
            next_store_queue.sw_data = curr_store_queue.sw_data; 
            next_store_queue.mem_addr = curr_store_queue.mem_addr; 
            next_store_queue.active_list_id = curr_store_queue.active_list_id; 
            next_store_queue.entry_available_bit = curr_store_queue.entry_available_bit; 
            next_store_queue.read_pointer = misprediction_store_queue.read_pointer; 
            next_store_queue.entry_write_pointer = curr_store_queue.entry_write_pointer; 
        end

        if (!load_store_queue_full)
        begin
            if (i_reg_data.valid)
            begin
                if (i_reg_data.is_load)
                begin
                    next_load_queue.entry_available_bit[curr_load_queue.entry_write_pointer] = 1'b0; 
                    next_load_queue.valid[curr_load_queue.entry_write_pointer] = 1'b0; 
                    next_load_queue.active_list_id[curr_load_queue.entry_write_pointer] = i_reg_data.active_list_id; 
                    next_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer + 1'b1; 
                end
                else if (i_reg_data.is_store)
                begin 
                    next_store_queue.entry_available_bit[curr_store_queue.entry_write_pointer] = 1'b0; 
                    next_store_queue.valid[curr_store_queue.entry_write_pointer] = 1'b0; 
                    next_store_queue.active_list_id[curr_store_queue.entry_write_pointer] = i_reg_data.active_list_id; 
                    next_store_queue.entry_write_pointer = curr_store_queue.entry_write_pointer + 1'b1;
                end
            end
        end

        if (i_agu_output.valid)
        begin
            if (curr_mem_queue.mem_action[i_scheduler.agu_dispatch_index] == READ)
            begin
                for (int i = 0; i < `LOAD_STORE_SIZE; i++)
                begin
                    cmpt_entry[i] = (curr_load_queue.active_list_id[i] == curr_mem_queue.active_list_id[i_scheduler.agu_dispatch_index] &&
                                        curr_load_queue.entry_available_bit[i] == 1'b0); 
                end
                next_load_queue.valid[cmpt_entry_index] = 1'b1; 
                next_load_queue.mem_addr[cmpt_entry_index] = i_agu_output.result[`ADDR_WIDTH - 1 : 0]; 
            end
            else 
            begin
                for (int i = 0; i < `LOAD_STORE_SIZE; i++)
                begin
                    cmpt_entry[i] = (curr_store_queue.active_list_id[i] == curr_mem_queue.active_list_id[i_scheduler.agu_dispatch_index] &&
                                        curr_store_queue.entry_available_bit[i] == 1'b0); 
                end
                next_store_queue.valid[cmpt_entry_index] = 1'b1; 
                next_store_queue.sw_data[cmpt_entry_index]  = curr_rename_state.merged_reg_file[curr_mem_queue.sw_src[i_scheduler.agu_dispatch_index]]; 
                next_store_queue.mem_addr[cmpt_entry_index] = i_agu_output.result[`ADDR_WIDTH - 1 : 0]; 
            end
        end

        if (!hazard_signal_in.dc_miss)
        begin 
            if (i_commit_out.queue_store)
            begin
                if (next_store_queue.valid[curr_store_queue.read_pointer] && !misprediction_store_queue.entry_available_bit[curr_store_queue.read_pointer])
                begin
                    next_store_queue.read_pointer = curr_store_queue.read_pointer + 1'b1; 
                end
            end
        end
    end


    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] store_traverse_pointer;
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_load_bypass; 
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_store_load_trap; 
    logic halt_load; 
    logic load_color_bit; 
    logic store_color_bit; 

    logic load_bypass_possible; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_bypass_index; 

    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_load_valid; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_dispatch_index; 
    logic load_dispatch_match; 

    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] d_cache_read_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_read_pointer; 

    priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) load_bypass_retriever (
		.x(cmpt_load_bypass),
		.bottom_up(1'b0),
		.valid_in(load_bypass_possible),
		.y(load_bypass_index)
	);


    priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
   ) store_load_trap_checker (
		.x(cmpt_store_load_trap),
		.bottom_up(1'b1),
		.valid_in(halt_load),
		.y()
	);

    priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) load_dispatch_retriever (
		.x(cmpt_load_valid),
		.bottom_up(1'b1),
		.valid_in(load_dispatch_match),
		.y(load_dispatch_index)
	);

    always_comb
    begin
        for (int i = 0; i < `LOAD_STORE_SIZE; i++)
        begin
            cmpt_load_valid[i] = next_load_queue.valid[curr_commit_state.load_commit_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]]; 
        end

        load_read_pointer = curr_commit_state.load_commit_pointer + load_dispatch_index; 
        load_color_bit = curr_active_state.color_bit[next_load_queue.active_list_id[load_read_pointer]]; 
        store_color_bit = 1'b0; 
        cmpt_load_bypass = '0;
        cmpt_store_load_trap = '0; 
        store_traverse_pointer = '0; 


        if (!i_commit_out.queue_store && load_dispatch_match)
        begin
            for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            begin
                store_traverse_pointer = curr_commit_state.store_commit_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]; 
                store_color_bit = curr_active_state.color_bit[next_store_queue.active_list_id[store_traverse_pointer]]; 
                if (store_color_bit == load_color_bit)
                begin
                    if (next_store_queue.active_list_id[store_traverse_pointer] < next_load_queue.active_list_id[load_read_pointer])
                    begin
                        if (next_store_queue.mem_addr[store_traverse_pointer] == next_load_queue.mem_addr[load_read_pointer] &&
                                next_store_queue.valid[store_traverse_pointer] && !misprediction_store_queue.entry_available_bit[store_traverse_pointer])
                            cmpt_load_bypass[i] = 1'b1;
                        if (!next_store_queue.entry_available_bit[store_traverse_pointer] && !next_store_queue.valid[store_traverse_pointer])
                            cmpt_store_load_trap[i] = 1'b1; 
                    end                
                end
                else 
                begin
                    if (next_store_queue.active_list_id[store_traverse_pointer] > next_load_queue.active_list_id[load_read_pointer])
                    begin
                        if (next_store_queue.mem_addr[store_traverse_pointer] == next_load_queue.mem_addr[load_read_pointer] &&
                                next_store_queue.valid[store_traverse_pointer])
                            cmpt_load_bypass[i] = 1'b1;
                        if (!next_store_queue.entry_available_bit[store_traverse_pointer] && !next_store_queue.valid[store_traverse_pointer])
                            cmpt_store_load_trap[i] = 1'b1; 
                    end       
                end
            end
        end
    end


    always_comb
    begin : dispatch_to_cache

        if (i_commit_out.queue_store)
        begin
            d_cache_read_pointer = curr_store_queue.read_pointer;

            o_d_cache_input.valid = next_store_queue.valid[d_cache_read_pointer] & !misprediction_store_queue.entry_available_bit[d_cache_read_pointer];
            o_d_cache_input.mem_action = WRITE; 
            o_d_cache_input.addr = next_store_queue.mem_addr[d_cache_read_pointer]; 
            o_d_cache_input.addr_next = next_store_queue.mem_addr[d_cache_read_pointer]; 
            o_d_cache_input.data = next_store_queue.sw_data[d_cache_read_pointer]; 

            o_d_cache_controls.valid = next_store_queue.valid[d_cache_read_pointer] & !misprediction_store_queue.entry_available_bit[d_cache_read_pointer];
            o_d_cache_controls.mem_action = WRITE;
            o_d_cache_controls.bypass_possible = 1'b0; 
            o_d_cache_controls.bypass_index = '0; 
            o_d_cache_controls.NOP = 1'b0; 
            o_d_cache_controls.dispatch_index = d_cache_read_pointer; 
        end
        else 
        begin
            d_cache_read_pointer = load_read_pointer; 

            o_d_cache_input.valid = load_dispatch_match & !load_bypass_possible & !halt_load & !misprediction_load_queue.entry_available_bit[d_cache_read_pointer]; 
            o_d_cache_input.mem_action = READ; 
            o_d_cache_input.addr = next_load_queue.mem_addr[d_cache_read_pointer]; 
            o_d_cache_input.addr_next = next_load_queue.mem_addr[d_cache_read_pointer]; 
            o_d_cache_input.data = '0; 

            o_d_cache_controls.valid = load_dispatch_match & !halt_load & !misprediction_load_queue.entry_available_bit[d_cache_read_pointer];
            o_d_cache_controls.mem_action = READ; 
            o_d_cache_controls.bypass_possible = load_bypass_possible; 
            o_d_cache_controls.bypass_index = load_bypass_index + curr_commit_state.store_commit_pointer;  
            o_d_cache_controls.NOP = 1'b0;
            o_d_cache_controls.dispatch_index = d_cache_read_pointer;
        end
    end

endmodule