interface load_queue_ifc();
    logic [`LOAD_STORE_SIZE - 1 : 0] entry_available_bit; 
    logic [`LOAD_STORE_SIZE - 1 : 0] valid; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] read_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] entry_write_pointer; 

    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] active_list_id [`LOAD_STORE_SIZE]; 
    logic [`ADDR_WIDTH - 1 : 0] mem_addr[`LOAD_STORE_SIZE]; 

    modport in (input valid, mem_addr, entry_available_bit, read_pointer, entry_write_pointer,
            active_list_id);
    modport out (output valid, mem_addr, entry_available_bit, read_pointer, entry_write_pointer,
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

interface global_controls_ifc (); 
    logic invalidate_d_cache_output; 

    modport in ( input invalidate_d_cache_output); 
    modport out ( output invalidate_d_cache_output);
endinterface

module load_store_queue (
    input rst_n,
    
    scheduler_output_ifc.in i_scheduler,
    reg_file_output_ifc.in i_reg_data, 
    agu_output_ifc.in i_agu_output,
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
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
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] read_pointer; 
    
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
            next_load_queue.read_pointer = '0; 
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
            next_load_queue.valid = curr_load_queue.valid; 
            next_load_queue.mem_addr = curr_load_queue.mem_addr; 
            next_load_queue.active_list_id = curr_load_queue.active_list_id; 
            next_load_queue.entry_available_bit = curr_load_queue.entry_available_bit; 
            next_load_queue.read_pointer = curr_load_queue.read_pointer; 
            next_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer; 

            next_store_queue.valid = curr_store_queue.valid; 
            next_store_queue.sw_data = curr_store_queue.sw_data; 
            next_store_queue.mem_addr = curr_store_queue.mem_addr; 
            next_store_queue.active_list_id = curr_store_queue.active_list_id; 
            next_store_queue.entry_available_bit = curr_store_queue.entry_available_bit; 
            next_store_queue.read_pointer = curr_store_queue.read_pointer; 
            next_store_queue.entry_write_pointer = curr_store_queue.entry_write_pointer; 
        end

        if (!load_store_queue_full)
        begin
            if (i_reg_data.valid)
            begin
                if (i_reg_data.is_load)
                begin
                    next_load_queue.entry_available_bit[curr_load_queue.entry_write_pointer] = 1'b0; 
                    next_load_queue.active_list_id[curr_load_queue.entry_write_pointer] = i_reg_data.active_list_id; 
                    next_load_queue.entry_write_pointer = curr_load_queue.entry_write_pointer + 1'b1; 
                end
                else if (i_reg_data.is_store)
                begin 
                    next_store_queue.entry_available_bit[curr_store_queue.entry_write_pointer] = 1'b0; 
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
    end


    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] store_traverse_pointer;
    logic [`LOAD_STORE_SIZE - 1 : 0] cmpt_load_bypass; 
    logic bypass_possible; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] bypass_index; 

    priority_encoder# (
		.m(`LOAD_STORE_SIZE),
		.n(`LOAD_STORE_SIZE_INDEX)
    ) load_bypass_retriever (
		.x(cmpt_load_bypass),
		.bottom_up(1'b0),
		.valid_in(bypass_possible),
		.y(bypass_index)
	);


    always_comb
    begin : dispatch_to_cache
        read_pointer = '0; 
        cmpt_load_bypass = '0;
        store_traverse_pointer = '0; 

        o_d_cache_input.valid = '0; 
        o_d_cache_input.mem_action = READ; 
        o_d_cache_input.addr = '0; 
        o_d_cache_input.addr_next = '0; 
        o_d_cache_input.data = '0; 

        o_d_cache_controls.bypass_possible = '0; 
        o_d_cache_controls.bypass_index = '0; 
        o_d_cache_controls.NOP = 1'b1;

        if (i_commit_out.queue_store)
        begin
            read_pointer = curr_store_queue.read_pointer;
            o_d_cache_input.valid = next_store_queue.valid[read_pointer]; 
            o_d_cache_input.mem_action = WRITE; 
            o_d_cache_input.addr = next_store_queue.mem_addr[read_pointer]; 
            o_d_cache_input.addr_next = next_store_queue.mem_addr[read_pointer]; 
            o_d_cache_input.data = next_store_queue.sw_data[read_pointer]; 

            o_d_cache_controls.bypass_possible = 1'b0; 
            o_d_cache_controls.bypass_index = '0; 
            o_d_cache_controls.NOP = 1'b0; 
        end
        else if (i_commit_out.queue_load)
        begin
            read_pointer = curr_load_queue.read_pointer; 

            // for (int i = 0; i < `LOAD_STORE_SIZE; i++)
            // begin
            //     store_traverse_pointer = curr_store_queue.read_pointer + i[`LOAD_STORE_SIZE_INDEX - 1 : 0]; 
            //     if (next_store_queue.valid[store_traverse_pointer] && 
            //             next_store_queue.pc[store_traverse_pointer] < next_load_queue.pc[read_pointer] &&
            //                 next_store_queue.mem_addr[store_traverse_pointer] == next_load_queue.mem_addr[read_pointer])
            //         cmpt_load_bypass[i] = 1'b1;
            // end

            o_d_cache_input.valid = next_load_queue.valid[read_pointer] & !bypass_possible; 
            o_d_cache_input.mem_action = READ; 
            o_d_cache_input.addr = next_load_queue.mem_addr[read_pointer]; 
            o_d_cache_input.addr_next = next_load_queue.mem_addr[read_pointer]; 
            o_d_cache_input.data = '0; 

            o_d_cache_controls.bypass_possible = '0; 
            o_d_cache_controls.bypass_index = bypass_index + curr_store_queue.read_pointer; 
            o_d_cache_controls.NOP = 1'b0;
        end
    end
endmodule