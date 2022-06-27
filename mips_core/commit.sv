interface commit_state_ifc (); 

    logic [`ACTIVE_LIST_SIZE - 1 : 0] entry_available_bit; 
	logic [`ACTIVE_LIST_SIZE - 1 : 0] ready_to_commit; 
	logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] oldest_inst_pointer; 
	logic [`PHYS_REG_NUM_INDEX - 1 : 0] free_tail_pointer; 
    logic [`BRANCH_NUM_INDEX - 1 : 0] branch_read_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] load_commit_pointer; 
    logic [`LOAD_STORE_SIZE_INDEX - 1 : 0] store_commit_pointer; 

	modport in (input ready_to_commit, oldest_inst_pointer, free_tail_pointer, 
            entry_available_bit, branch_read_pointer, load_commit_pointer, store_commit_pointer);  
	modport out (output ready_to_commit, oldest_inst_pointer, free_tail_pointer,
            entry_available_bit, branch_read_pointer, load_commit_pointer, store_commit_pointer);  

endinterface

interface commit_output_ifc (); 
    logic queue_store; 
    logic commit_valid; 
    logic [`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] last_valid_commit_idx; 
	logic [`COMMIT_WINDOW_SIZE - 1 : 0] reclaim_valid; 
    logic [`COMMIT_WINDOW_SIZE - 1 : 0] load_valid;  
    logic [`COMMIT_WINDOW_SIZE - 1 : 0] store_valid; 
    logic [`COMMIT_WINDOW_SIZE - 1 : 0] branch_valid; 

	logic [`PHYS_REG_NUM_INDEX - 1 : 0] reclaim_reg [`COMMIT_WINDOW_SIZE];

	modport in (input reclaim_valid, load_valid, store_valid, branch_valid, queue_store, reclaim_reg, 
        last_valid_commit_idx, commit_valid);    
	modport out (output reclaim_valid, load_valid, store_valid, branch_valid, queue_store, reclaim_reg, 
        last_valid_commit_idx, commit_valid);    

endinterface

module commit (
    input clk,
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
    hazard_signals_ifc.in hazard_signal_in, 
    misprediction_output_ifc.in misprediction_out, 
    alu_input_ifc.in alu_input, 
	commit_output_ifc.out o_commit_out,
	commit_state_ifc.out next_commit_state, 
    simulation_verification_ifc.out simulation_verification
);

    logic [`COMMIT_WINDOW_SIZE - 1 : 0] cmpt_commit_valid; 
    logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] commit_traverse_pointer;
    logic window_not_full; 
    logic [`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] commit_idx; 
    logic [`COMMIT_WINDOW_SIZE - 1 : 0] cmpt_commit_num; 

    int num_loads, num_stores, num_branches, num_writes, branch_counter; 
    
    always_comb
    begin
        num_loads = 0; 
        num_stores = 0; 
        num_branches = 0; 
        num_writes = 0; 

        if (!rst_n)
        begin
            next_commit_state.ready_to_commit = '0;
            next_commit_state.oldest_inst_pointer = '0; 
            next_commit_state.free_tail_pointer = '0;  
            next_commit_state.branch_read_pointer = '0; 
            next_commit_state.entry_available_bit = {`ACTIVE_LIST_SIZE{1'b1}}; 
            next_commit_state.load_commit_pointer = '0; 
            next_commit_state.store_commit_pointer = '0; 
        end
        else 
        begin
            next_commit_state.ready_to_commit = curr_commit_state.ready_to_commit; 
            next_commit_state.oldest_inst_pointer = curr_commit_state.oldest_inst_pointer; 
            next_commit_state.free_tail_pointer = curr_commit_state.free_tail_pointer; 
            next_commit_state.branch_read_pointer = curr_commit_state.branch_read_pointer; 
            next_commit_state.entry_available_bit = curr_commit_state.entry_available_bit; 
            next_commit_state.load_commit_pointer = curr_commit_state.load_commit_pointer; 
            next_commit_state.store_commit_pointer = curr_commit_state.store_commit_pointer; 
        end

        if (i_int_commit.valid) 
        begin
            next_commit_state.ready_to_commit[i_int_commit.active_list_id] = 1'b1; 
        end

        if (i_mem_commit.valid)
        begin
            next_commit_state.ready_to_commit[i_mem_commit.active_list_id] = 1'b1; 
        end

        if (hazard_signal_in.branch_miss)
        begin
            next_commit_state.ready_to_commit[misprediction_out.branch_id_with_ds + 1'b1] = 1'b0; 
        end

        o_commit_out.commit_valid = !window_not_full ? 1'b1 : (commit_idx == '0 ? 1'b0 : 1'b1); 
        o_commit_out.last_valid_commit_idx = !window_not_full ? (`COMMIT_WINDOW_SIZE - 1) : commit_idx - 1'b1; 


        for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
        begin
            if (o_commit_out.commit_valid)
            begin
                if (o_commit_out.branch_valid[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]] && i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] <= o_commit_out.last_valid_commit_idx)
                    num_branches++; 
                if (o_commit_out.load_valid[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]] && i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] <= o_commit_out.last_valid_commit_idx)
                    num_loads++; 
                if (o_commit_out.store_valid[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]] && i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] <= o_commit_out.last_valid_commit_idx)
                    num_stores++;
                if (o_commit_out.reclaim_valid[i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0]] && i[`COMMIT_WINDOW_SIZE_INDEX - 1 : 0] <= o_commit_out.last_valid_commit_idx)
                    num_writes++;
                if (i <= o_commit_out.last_valid_commit_idx)
                begin
                    next_commit_state.entry_available_bit[curr_commit_state.oldest_inst_pointer + i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0]] = 1'b1; 
                end
                    
            end
        end

        if (o_commit_out.commit_valid) 
        begin
            next_commit_state.oldest_inst_pointer = curr_commit_state.oldest_inst_pointer + o_commit_out.last_valid_commit_idx + 1'b1; 
            next_commit_state.free_tail_pointer = curr_commit_state.free_tail_pointer + num_writes[`PHYS_REG_NUM_INDEX - 1 : 0]; 
            next_commit_state.load_commit_pointer = curr_commit_state.load_commit_pointer + num_loads[`LOAD_STORE_SIZE_INDEX - 1 : 0]; 
            next_commit_state.store_commit_pointer = curr_commit_state.store_commit_pointer + num_stores[`LOAD_STORE_SIZE_INDEX - 1 : 0]; 
            next_commit_state.branch_read_pointer = curr_commit_state.branch_read_pointer + num_branches[`BRANCH_NUM_INDEX - 1 : 0]; 
        end 

        o_commit_out.queue_store = curr_active_state.is_store[next_commit_state.oldest_inst_pointer] ? 1'b1 : 1'b0; 
    end

    always_comb
    begin
        branch_counter = 0; 

        cmpt_commit_valid = '0; 

        o_commit_out.reclaim_reg = '{default: 0}; 
        o_commit_out.reclaim_valid = '0; 
        o_commit_out.load_valid = '0; 
        o_commit_out.store_valid = '0;  
        o_commit_out.branch_valid = '0; 

        for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
        begin
            commit_traverse_pointer = curr_commit_state.oldest_inst_pointer + i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0]; 
            if (next_commit_state.ready_to_commit[commit_traverse_pointer])
            begin
                cmpt_commit_valid[i] = 1'b1; 

                if (curr_branch_state.branch_id[curr_commit_state.branch_read_pointer + branch_counter[`BRANCH_NUM_INDEX - 1 : 0]] == commit_traverse_pointer &&
                    curr_branch_state.valid[curr_commit_state.branch_read_pointer + branch_counter[`BRANCH_NUM_INDEX - 1 : 0]])
                begin
                    o_commit_out.branch_valid[i] = 1'b1; 
                    branch_counter++; 
                end

                if (curr_active_state.uses_rw[commit_traverse_pointer])
                begin
                    o_commit_out.reclaim_valid[i] = 1'b1; 
                    o_commit_out.reclaim_reg[i] = curr_active_state.reclaim_list[commit_traverse_pointer]; 
                end

                if (curr_active_state.is_load[commit_traverse_pointer])
                begin
                    o_commit_out.load_valid[i] = 1'b1; 
                end
                else if (curr_active_state.is_store[commit_traverse_pointer])
                begin
                    o_commit_out.store_valid[i] = 1'b1; 
                end
            end
        end
    end

    priority_encoder# (
		.m(`COMMIT_WINDOW_SIZE),
		.n(`COMMIT_WINDOW_SIZE_INDEX)
    ) num_commits_retriever (
		.x(~cmpt_commit_valid),
		.bottom_up(1'b1),
		.valid_in(window_not_full),
		.y(commit_idx)
	);

    `ifdef SIMULATION
        logic signed [`DATA_WIDTH - 1 : 0] op2 [`ACTIVE_LIST_SIZE];
        logic [`PHYS_REG_NUM_INDEX - 1 : 0] phys_rw;
        logic [`ACTIVE_LIST_SIZE_INDEX - 1 : 0] sim_traverse_pointer;
        int load_counter, store_counter;  
        always_comb
            begin
                load_counter = 0; 
                store_counter = 0; 

                phys_rw = '0; 

                simulation_verification.valid = '0; 
                simulation_verification.op2 = '{default: 0}; 
                simulation_verification.uses_rw = '0; 
                simulation_verification.rw_addr = '{default: 0}; 
                simulation_verification.data = '{default: 0}; 
                simulation_verification.is_store = '0;
                simulation_verification.is_load = '0; 
                simulation_verification.mem_addr = '{default: 0};  
                simulation_verification.pc = '{default: 0}; 
                simulation_verification.active_list_id = '{default : 0}; 

                for (int i = 0; i < `COMMIT_WINDOW_SIZE; i++)
                begin
                    sim_traverse_pointer = curr_commit_state.oldest_inst_pointer + i[`ACTIVE_LIST_SIZE_INDEX - 1 : 0]; 
                    if (next_commit_state.ready_to_commit[sim_traverse_pointer])
                    begin

                        simulation_verification.valid[i] = 1'b1; 
                        simulation_verification.active_list_id[i] = sim_traverse_pointer; 
                        simulation_verification.pc[i] = curr_active_state.pc[sim_traverse_pointer]; 
                        simulation_verification.op2[i] = op2[sim_traverse_pointer]; 
                        if (curr_active_state.uses_rw[sim_traverse_pointer])
                        begin
                            phys_rw = curr_active_state.rw_addr[sim_traverse_pointer]; 
                            simulation_verification.uses_rw[i] = 1'b1; 
                            simulation_verification.rw_addr[i] = curr_rename_state.reverse_rename_map[phys_rw]; 
                            simulation_verification.data[i] = next_rename_state.merged_reg_file[phys_rw]; 
                        end

                        if (curr_active_state.is_load[sim_traverse_pointer])
                        begin
                            simulation_verification.is_load[i] = 1'b1; 
                            simulation_verification.mem_addr[i] = curr_load_queue.mem_addr[curr_commit_state.load_commit_pointer + load_counter[`LOAD_STORE_SIZE_INDEX - 1 : 0]]; 
                            load_counter++; 
                        end
                        else if (curr_active_state.is_store[sim_traverse_pointer])
                        begin
                            simulation_verification.is_store[i] = 1'b1; 
                            simulation_verification.mem_addr[i] = curr_store_queue.mem_addr[curr_commit_state.store_commit_pointer + store_counter[`LOAD_STORE_SIZE_INDEX - 1 : 0]]; 
                            simulation_verification.data[i] = curr_store_queue.sw_data[curr_commit_state.store_commit_pointer + store_counter[`LOAD_STORE_SIZE_INDEX - 1 : 0]];  
                            store_counter++; 
                        end
                    end
                end
            end

        always_ff @(posedge clk)
        begin
            if (!rst_n)
                op2 <= '{default: 0}; 
            else if (i_int_commit.valid)
                op2[i_int_commit.active_list_id] <= alu_input.op2; 
        end
    `endif
endmodule