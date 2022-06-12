interface commit_state_ifc (); 

    logic [`ACTIVE_LIST_SIZE - 1 : 0] entry_available_bit; 
	logic ready_to_commit[`ACTIVE_LIST_SIZE]; 
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] oldest_inst_pointer; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_tail_pointer; 
    logic [`BRANCH_NUM_INDEX - 1 : 0] branch_read_pointer; 

	modport in (input ready_to_commit, oldest_inst_pointer, free_tail_pointer, 
            entry_available_bit, branch_read_pointer);  
	modport out (output ready_to_commit, oldest_inst_pointer, free_tail_pointer,
            entry_available_bit, branch_read_pointer);  

endinterface

interface commit_output_ifc (); 
	logic reclaim_valid; 
    logic queue_store; 
    logic queue_load; 
    logic load_done; 
    logic store_done; 
    logic branch_done; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_tail_pointer; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] oldest_inst_pointer; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] reclaim_reg;

	modport in (input reclaim_valid, load_done, store_done, queue_store, free_tail_pointer, reclaim_reg, oldest_inst_pointer, queue_load, 
            branch_done);  
	modport out (output reclaim_valid, load_done, store_done, queue_store, free_tail_pointer, reclaim_reg, oldest_inst_pointer, queue_load, 
            branch_done);  

endinterface

module commit (
    input rst_n,

    inst_commit_ifc.in i_int_commit,
    inst_commit_ifc.in i_mem_commit,
    commit_state_ifc.in curr_commit_state,
	active_state_ifc.in curr_active_state,
    rename_ifc.in curr_rename_state, 
    rename_ifc.in next_rename_state, 
    load_queue_ifc.in curr_load_queue, 
    store_queue_ifc.in curr_store_queue, 
    branch_state_ifc.in curr_branch_state,

	commit_output_ifc.out o_commit_out,
	commit_state_ifc.out next_commit_state, 
    simulation_verification_ifc.out simulation_verification
);

    logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rw;

    always_comb
    begin
        o_commit_out.reclaim_valid = 1'b0; 
        o_commit_out.reclaim_reg = '0; 
        o_commit_out.load_done = 1'b0; 
        o_commit_out.store_done = 1'b0; 
        o_commit_out.branch_done = 1'b0; 
        o_commit_out.free_tail_pointer = curr_commit_state.free_tail_pointer; 
        o_commit_out.oldest_inst_pointer = curr_commit_state.oldest_inst_pointer; 

        simulation_verification.valid = 1'b0; 
        simulation_verification.uses_rw = 1'b0; 
        simulation_verification.rw_addr = '0; 
        simulation_verification.data = '0; 
        simulation_verification.is_store = 1'b0;
        simulation_verification.is_load = 1'b0; 
        simulation_verification.mem_addr = '0; 
        simulation_verification.pc = '0; 

        phys_rw = '0; 

        if (!rst_n)
        begin
            next_commit_state.ready_to_commit = '{default : 1'b0};
            next_commit_state.oldest_inst_pointer = '0; 
            next_commit_state.free_tail_pointer = '0;  
            next_commit_state.branch_read_pointer = '0; 
            next_commit_state.entry_available_bit = {`ACTIVE_LIST_SIZE{1'b1}}; 
        end
        else 
        begin
            next_commit_state.ready_to_commit = curr_commit_state.ready_to_commit; 
            next_commit_state.oldest_inst_pointer = curr_commit_state.oldest_inst_pointer; 
            next_commit_state.free_tail_pointer = curr_commit_state.free_tail_pointer; 
            next_commit_state.branch_read_pointer = curr_commit_state.branch_read_pointer; 
            next_commit_state.entry_available_bit = curr_commit_state.entry_available_bit; 
        end

        if (i_int_commit.valid) 
        begin
            next_commit_state.ready_to_commit[i_int_commit.active_list_id] = 1'b1; 
        end

        if (i_mem_commit.valid)
        begin
            next_commit_state.ready_to_commit[i_mem_commit.active_list_id] = 1'b1; 
        end

        if (next_commit_state.ready_to_commit[curr_commit_state.oldest_inst_pointer])
        begin
            if (curr_branch_state.branch_id[curr_commit_state.branch_read_pointer] == curr_commit_state.oldest_inst_pointer &&
                curr_branch_state.valid[curr_commit_state.branch_read_pointer])
            begin
                o_commit_out.branch_done = 1'b1; 
                next_commit_state.branch_read_pointer = curr_commit_state.branch_read_pointer + 1'b1; 
            end

            simulation_verification.valid = 1'b1; 
            simulation_verification.pc = curr_active_state.pc[curr_commit_state.oldest_inst_pointer]; 

            if (curr_active_state.uses_rw[curr_commit_state.oldest_inst_pointer])
            begin
                phys_rw = curr_active_state.rw_addr[curr_commit_state.oldest_inst_pointer]; 
                simulation_verification.uses_rw = 1'b1; 
                simulation_verification.rw_addr = curr_rename_state.reverse_rename_map[phys_rw]; 
                simulation_verification.data = next_rename_state.merged_reg_file[phys_rw]; 
                o_commit_out.reclaim_valid = 1'b1; 
                o_commit_out.reclaim_reg = curr_active_state.reclaim_list[curr_commit_state.oldest_inst_pointer]; 
                next_commit_state.free_tail_pointer = curr_commit_state.free_tail_pointer + 1'b1; 
            end

            if (curr_active_state.is_load[curr_commit_state.oldest_inst_pointer])
            begin
                o_commit_out.load_done = 1'b1; 
                simulation_verification.is_load = 1'b1; 
                simulation_verification.mem_addr = curr_load_queue.mem_addr[curr_load_queue.read_pointer]; 
            end

            if (curr_active_state.is_store[curr_commit_state.oldest_inst_pointer])
            begin
                o_commit_out.store_done = 1'b1; 
                simulation_verification.is_store = 1'b1; 
                simulation_verification.mem_addr = curr_store_queue.mem_addr[curr_store_queue.read_pointer]; 
                simulation_verification.data = curr_store_queue.sw_data[curr_store_queue.read_pointer]; 
            end

            next_commit_state.oldest_inst_pointer = curr_commit_state.oldest_inst_pointer + 1'b1; 
            next_commit_state.entry_available_bit[curr_commit_state.oldest_inst_pointer] = 1'b1; 
            next_commit_state.ready_to_commit[curr_commit_state.oldest_inst_pointer] = 1'b0; 
        end

        o_commit_out.queue_store = curr_active_state.is_store[next_commit_state.oldest_inst_pointer] ? 1'b1 : 1'b0; 
        o_commit_out.queue_load = curr_active_state.is_load[next_commit_state.oldest_inst_pointer] ? 1'b1 : 1'b0;
    end

endmodule