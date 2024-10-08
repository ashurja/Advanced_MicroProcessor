module TAGE  (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	branch_controls_ifc.in curr_branch_controls,
	branch_controls_ifc.in misprediction_branch_controls, 

	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);
	localparam INDEX_WIDTH_TABLES = (`TAGE_TABLE_NUM > 1) ? $clog2(`TAGE_TABLE_NUM) : 1; 
	localparam BASE_LEN = 4096; 

    logic fb_valid; 

	logic [`TAGE_TABLE_NUM - 1 : 0] curr_u_bits_from_all_t; 
	logic [`TAGE_TABLE_NUM - 1 : 0] prev_u_bits_from_all_t; 
	logic [`TAGE_TABLE_NUM - 1 : 0] curr_hits_from_all_t; 
	logic [`TAGE_TABLE_NUM - 1 : 0] curr_alt_hits_from_all_t; 
	logic [`TAGE_TABLE_NUM - 1 : 0] curr_pred_from_all_t; 
	logic [`TAGE_TABLE_NUM - 1 : 0] prev_pred_from_all_t; 

	logic [`TAGE_TABLE_NUM - 1 : 0] table_search_for_evict; 
	logic [`TAGE_TABLE_NUM - 1 : 0] tables_with_evict_slots; 
	logic [`TAGE_TABLE_NUM - 1 : 0] select_t_for_evict; 
	logic [`TAGE_TABLE_NUM - 1 : 0] select_t_for_age; 
	logic [`TAGE_TABLE_NUM - 1 : 0] update_u_counters; 
	logic [`TAGE_TABLE_NUM - 1 : 0] update_prediction_counters; 

	logic [INDEX_WIDTH_TABLES - 1 : 0] curr_t_index_for_pred; 
	logic [INDEX_WIDTH_TABLES - 1 : 0] prev_t_index_for_pred; 
	logic [INDEX_WIDTH_TABLES - 1 : 0] curr_t_index_for_alt_pred; 
	logic [INDEX_WIDTH_TABLES - 1 : 0] prev_t_index_for_alt_pred; 
	logic [INDEX_WIDTH_TABLES - 1 : 0] t_index_for_evict; 

	logic eviction_index_found; 
	logic [`ADDR_WIDTH - 1 : 0] i_req_prev_pc; 

	logic reset_u_counters; 
	logic [17 : 0] counter_for_u_reset; 

	logic choose_u_lsb_msb; 
	logic reset_u_lsb; 
	logic reset_u_msb; 

	always_comb begin : setup
        fb_valid = i_fb_valid; 
		reset_u_counters = 1'b0; 
		reset_u_lsb = 1'b0; 
		reset_u_msb = 1'b0; 

		if (counter_for_u_reset == 256000)
		begin
			reset_u_counters = 1'b1;
			if (choose_u_lsb_msb) reset_u_lsb = 1'b1; 
			else reset_u_msb = 1'b1; 
		end 
 
	end

	BASE_PREDICTOR#  (
		.BASE_LEN
	) bi_modal_2bit (
		.clk,
		.rst_n,
		.i_req_valid, 
		.i_req_pc, 
		.i_req_target, 
		.o_req_prediction(curr_pred_from_all_t[0]), 
		.i_fb_valid(fb_valid), 
		.i_fb_pc, 
		.i_fb_prediction, 
		.i_fb_outcome
	); 

	genvar g;
	generate
		for (g = 0; g < `TAGE_TABLE_NUM - 1; g++)
		begin : tables
            TABLE# (
                .TABLE_LEN(`TAGE_TABLE_LEN),
                .TAG_WIDTH(`TAGE_TAG_WIDTH)
            ) component (
                .clk,
                .rst_n,
                .i_req_valid, 
                .i_req_pc, 
                .i_req_target, 
                .i_fb_valid(fb_valid), 
                .i_fb_pc, 
                .i_fb_prediction, 
                .i_fb_outcome,
                .final_prediction(o_req_prediction),
                .reset_u_lsb, 
                .reset_u_msb,
                .table_select_evict(table_search_for_evict[g + 1]),
                .evict(select_t_for_evict[g + 1]),
                .age(select_t_for_age[g + 1]),
                .update_u_counter(update_u_counters[g + 1]),
                .update_pred_counter(update_prediction_counters[g + 1]),
				.CSR_IDX(curr_branch_controls.CSR_IDX[g]), 
				.CSR_TAG(curr_branch_controls.CSR_TAG[g]), 
				.CSR_TAG_2(curr_branch_controls.CSR_TAG_2[g]),

				.CSR_IDX_FEED(misprediction_branch_controls.CSR_IDX_FEED[g]), 
				.CSR_TAG_FEED(misprediction_branch_controls.CSR_TAG_FEED[g]), 
				.CSR_TAG_2_FEED(misprediction_branch_controls.CSR_TAG_2_FEED[g]),
                .GHR(curr_branch_controls.GHR),
                .prediction(curr_pred_from_all_t[g + 1]),
                .hit(curr_hits_from_all_t[g + 1]), 
                .u_bit(curr_u_bits_from_all_t[g + 1]),
                .eviction_possible(tables_with_evict_slots[g + 1])
            ); 
		end
	endgenerate


	always_comb
	begin : setup_base_predictor
		curr_hits_from_all_t[0] = 1'b0; 
		curr_u_bits_from_all_t[0] = 1'b0; 
		if (i_req_valid)
		begin
			curr_hits_from_all_t[0] = 1'b1; 
			curr_u_bits_from_all_t[0] = 1'b1; 
		end
	end

	priority_encoder# (
		.m(`TAGE_TABLE_NUM),
		.n(INDEX_WIDTH_TABLES)
	) pred_index_retriever (
		.x(curr_hits_from_all_t),
		.bottom_up(1'b0),
		.valid_in(),
		.y(curr_t_index_for_pred)
	); 

	always_comb
	begin
		curr_alt_hits_from_all_t = curr_hits_from_all_t; 
		curr_alt_hits_from_all_t[curr_t_index_for_pred] = 1'b0; 
	end

	priority_encoder# (
		.m(`TAGE_TABLE_NUM),
		.n(INDEX_WIDTH_TABLES)
	) altpred_index_retriever (
		.x(curr_alt_hits_from_all_t),
		.bottom_up(1'b0),
		.valid_in(),
		.y(curr_t_index_for_alt_pred)
	); 

	always_comb 
	begin : make_the_prediction
		o_req_prediction = 1'b0; 
		if (i_req_valid) 
		begin
			o_req_prediction = curr_pred_from_all_t[curr_t_index_for_pred]; 
		end

	end


/******* SECTION FOR UPDATES **********/

	always_comb
	begin : look_for_table_to_evict
		table_search_for_evict = 0; 
		if (fb_valid && (i_fb_prediction != i_fb_outcome))
		begin
			for (int i = 0; i < `TAGE_TABLE_NUM - prev_t_index_for_pred + 1; i++)
			begin
				table_search_for_evict[prev_t_index_for_pred + 1 + i] = 1'b1; 
			end
		end
	end

	priority_encoder# (
		.m(`TAGE_TABLE_NUM),
		.n(INDEX_WIDTH_TABLES)
	) evict_index_retriever (
		.x(tables_with_evict_slots),
		.bottom_up(1'b1),
		.valid_in(eviction_index_found),
		.y(t_index_for_evict)
	); 

	always_comb
	begin : select_which_table_to_evict_or_age_or_update
		select_t_for_evict = 0; 
		select_t_for_age = 0; 
		update_u_counters = 0; 
		update_prediction_counters = 0; 

		if (fb_valid && (i_fb_prediction != i_fb_outcome))
		begin
			if (eviction_index_found)	
			begin
				select_t_for_evict[t_index_for_evict] = 1'b1; 
			end

			else 
			begin
				for (int i = 0; i < `TAGE_TABLE_NUM - prev_t_index_for_pred + 1; i++)
				begin
					select_t_for_age[prev_t_index_for_pred + 1 + i] = 1'b1; 
				end
			end
		end
		
		if (fb_valid)
		begin
			update_prediction_counters[prev_t_index_for_pred] = 1'b1; 
			if (!prev_u_bits_from_all_t[prev_t_index_for_pred])
			begin
				update_prediction_counters[prev_t_index_for_alt_pred] = 1'b1; 
			end
		end

		if (fb_valid)
		begin
			if (i_fb_prediction != prev_pred_from_all_t[prev_t_index_for_alt_pred])
			begin
				update_u_counters[prev_t_index_for_pred] = 1'b1; 
			end
		end
	end

	always_ff @(posedge clk)
	begin : save_curr_states
		if (!rst_n)
		begin
			prev_u_bits_from_all_t <= 0; 
			prev_pred_from_all_t <= 0; 
			prev_t_index_for_pred <= 0; 
			prev_t_index_for_alt_pred <= 0; 
			i_req_prev_pc <= 0; 
		end
		else 
		begin
			prev_u_bits_from_all_t <= curr_u_bits_from_all_t; 
			prev_pred_from_all_t <= curr_pred_from_all_t; 
			prev_t_index_for_pred <= curr_t_index_for_pred; 
			prev_t_index_for_alt_pred <= curr_t_index_for_alt_pred; 
			i_req_prev_pc <= i_req_pc; 
		end
	end


	always_ff @(posedge clk) 
	begin : resets
		if (!rst_n)
		begin
			counter_for_u_reset <= 0; 
			choose_u_lsb_msb <= 1'b0; 
		end
		else if (i_req_pc != i_req_prev_pc)
		begin
			if (reset_u_counters)
			begin
				counter_for_u_reset <= 0; 
				choose_u_lsb_msb <= !choose_u_lsb_msb; 
			end
			else if (i_req_valid)
			begin
				counter_for_u_reset <= counter_for_u_reset + 1'b1;
			end
		end
	end
		

	`ifdef SIMULATION
		always_ff @(posedge clk)
		begin
			if (fb_valid)
			begin
				if (i_fb_prediction != i_fb_outcome) 
				begin
					if (prev_t_index_for_pred == 0) stats_event("BASE_miss");
					else if (prev_t_index_for_pred == 1) stats_event("TABLE1_miss");
					else if (prev_t_index_for_pred == 2) stats_event("TABLE2_miss");
					else if (prev_t_index_for_pred == 3) stats_event("TABLE3_miss");
					else if (prev_t_index_for_pred == 4) stats_event("TABLE4_miss");
					else if (prev_t_index_for_pred == 5) stats_event("TABLE5_miss");
					else if (prev_t_index_for_pred == 6) stats_event("TABLE6_miss");
					else if (prev_t_index_for_pred == 7) stats_event("TABLE7_miss");
					else if (prev_t_index_for_pred == 8) stats_event("TABLE8_miss");
				end
				else 
				begin
					if (prev_t_index_for_pred == 0) stats_event("BASE_hit");
					else if (prev_t_index_for_pred == 1) stats_event("TABLE1_hit");
					else if (prev_t_index_for_pred == 2) stats_event("TABLE2_hit");
					else if (prev_t_index_for_pred == 3) stats_event("TABLE3_hit");
					else if (prev_t_index_for_pred == 4) stats_event("TABLE4_hit");
					else if (prev_t_index_for_pred == 5) stats_event("TABLE5_hit");
					else if (prev_t_index_for_pred == 6) stats_event("TABLE6_hit");
					else if (prev_t_index_for_pred == 7) stats_event("TABLE7_hit");
					else if (prev_t_index_for_pred == 8) stats_event("TABLE8_hit");
				end
			end
		end
	`endif
endmodule


/********************************** TABLE **********************************
****************************************************************************
****************************************************************************/



module TABLE #(
    parameter TABLE_LEN, 
    parameter TAG_WIDTH
) (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low
    
	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome,

    input mips_core_pkg::BranchOutcome final_prediction, 

	input logic [INDEX_WIDTH - 1 : 0] CSR_IDX, 
	input logic [TAG_WIDTH - 1 : 0] CSR_TAG, 
	input logic [TAG_WIDTH -2 : 0] CSR_TAG_2, 

	input logic [INDEX_WIDTH - 1 : 0] CSR_IDX_FEED, 
	input logic [TAG_WIDTH - 1 : 0] CSR_TAG_FEED, 
	input logic [TAG_WIDTH -2 : 0] CSR_TAG_2_FEED, 

	input table_select_evict,
	input evict, 
	input age,
	input update_pred_counter, 
	input update_u_counter,
	input logic [`GHR_LEN - 1 : 0] GHR, 
	input reset_u_lsb,
	input reset_u_msb, 

	output mips_core_pkg::BranchOutcome prediction,

	output hit, 
	output u_bit, 
	output eviction_possible
); 
	localparam INDEX_WIDTH = $clog2(TABLE_LEN); 

    logic [TAG_WIDTH - 1 : 0] tagbank [TABLE_LEN]; 
	logic [TAG_WIDTH - 1 : 0] update_tag; 
	logic [TAG_WIDTH - 1 : 0] i_tag; 

    logic [2 : 0] prediction_counter [TABLE_LEN]; 
    logic [1 : 0] u_counter [TABLE_LEN]; 
	logic [1 : 0] u_counter_next [TABLE_LEN]; 
	logic valid_entry [TABLE_LEN]; 


	logic [INDEX_WIDTH - 1 : 0] i_index;
	logic [INDEX_WIDTH - 1 : 0] update_index; 
	logic [INDEX_WIDTH - 1 : 0] evict_index; 
	
	always_comb 
	begin : compute_index_and_tag
		i_tag = 0; 
		i_index = 0; 
		if (i_req_valid)
		begin
			i_tag = CSR_TAG ^ i_fb_pc[TAG_WIDTH - 1 : 0] ^ {1'b0,CSR_TAG_2}; 
			i_index = CSR_IDX ^ i_fb_pc[INDEX_WIDTH - 1 : 0] ^ i_fb_pc[INDEX_WIDTH * 2 - 1 : INDEX_WIDTH]; 
		end
	end

	always_comb
	begin 
		update_index = CSR_IDX_FEED ^ i_fb_pc[INDEX_WIDTH - 1 : 0] ^ i_fb_pc[INDEX_WIDTH * 2 - 1 : INDEX_WIDTH]; 
		evict_index = update_index; 
		update_tag = CSR_TAG_FEED ^ i_fb_pc[TAG_WIDTH - 1 : 0] ^ {1'b0,CSR_TAG_2_FEED}; 
	end

	always_comb
	begin : check_for_hit
		hit = 1'b0; 
		if (i_req_valid)
		begin
			hit = (i_tag == tagbank[i_index]); 
		end
	end

	always_comb
	begin
		prediction = 1'b0; 
		u_bit = 1'b0; 
		if (i_req_valid)
		begin
			prediction = prediction_counter[i_index][2]; 
			u_bit = u_counter[i_index][1]; 
		end
	end

/******************************* UPDATE SECTION) **************/ 
	always_comb
	begin : check_for_eviction
		eviction_possible = 1'b0; 
		if (table_select_evict)
		begin
			eviction_possible = ((u_counter[evict_index] == 2'b00) && (valid_entry[evict_index] == 1'b1)); 
		end
	end

	always_comb
	begin
		u_counter_next = u_counter; 
		if (reset_u_msb)
		begin
			for (int i = 0; i < TABLE_LEN; i++)
			begin
				u_counter_next[i][1] = 1'b0; 
			end
		end

		else if (reset_u_lsb)
		begin
			for (int i = 0; i < TABLE_LEN; i++)
			begin
				u_counter_next[i][0] = 1'b0; 
			end
		end
	end

	always_ff @(posedge clk)
	begin : allocate_tags
		if (~rst_n)
		begin
			tagbank <= '{default: 0};
		end
		else if (evict)
		begin
			tagbank[evict_index] <= update_tag; 
		end
	end

	always_ff @(posedge clk)
	begin : update_prediction_counters
		if(~rst_n)
		begin
			prediction_counter <= '{default: 3'b100};	// Weakly taken
		end
		else
		begin
			if (i_fb_valid)
			begin
				if (update_pred_counter)
				begin
					case (i_fb_outcome)
						NOT_TAKEN: 
							begin
								if (prediction_counter[update_index] > 3'b000) prediction_counter[update_index] <= prediction_counter[update_index] - 3'b001; 
							end
						TAKEN:   
							begin
								if (prediction_counter[update_index] < 3'b111) prediction_counter[update_index] <= prediction_counter[update_index] + 3'b001; 
							end
					endcase
				end
				else if (evict)
				begin
					if (i_fb_outcome == TAKEN)
						prediction_counter[evict_index] <= 3'b100; 
					else 
						prediction_counter[evict_index] <= 3'b011; 
				end
			end
		end
	end



	always_ff @(posedge clk)
	begin : update_useful_counters
		if(~rst_n)
		begin
			u_counter <= '{default: 2'b00};	
		end
		else
		begin
			if (reset_u_msb)
			begin
				u_counter <= u_counter_next; 
			end

			else if (reset_u_lsb)
			begin
				u_counter <= u_counter_next; 
			end

			else if (i_fb_valid)
			begin
				if (update_u_counter)
				begin
					if (i_fb_prediction == i_fb_outcome)
					begin
						if (u_counter[update_index] < 2'b11) u_counter[update_index] <= u_counter[update_index] + 2'b01; 
					end
					else 
					begin
						if (u_counter[update_index] > 2'b00) u_counter[update_index] <= u_counter[update_index] - 2'b01; 
					end
				end

				else if (evict) 
				begin
					u_counter[evict_index] <= 2'b00; 
				end
				else if (age)
				begin
					if (u_counter[evict_index] > 2'b00) u_counter[evict_index] <= u_counter[evict_index] - 2'b01; 
				end
			end
		end
	end


	always_ff @(posedge	clk) 
	begin : update_valid_bits
		if (!rst_n)
		begin	
			valid_entry <= '{default : 1'b1}; 
		end
		else 
		begin
			if (i_req_valid & hit)
			begin
				valid_entry[i_index] <= 1'b1; 
			end

			if (i_fb_valid & evict)
			begin
				valid_entry[evict_index] <= 1'b0; 
			end
		end
	end
endmodule



/***********************************************************************
***********************************************************************
***********************************************************************/

module BASE_PREDICTOR #(
	parameter BASE_LEN
	) (
	input clk,    // Clock
	input rst_n,  // Synchronous reset active low

	// Request
	input logic i_req_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_pc,
	input logic [`ADDR_WIDTH - 1 : 0] i_req_target,
	output mips_core_pkg::BranchOutcome o_req_prediction,

	// Feedback
	input logic i_fb_valid,
	input logic [`ADDR_WIDTH - 1 : 0] i_fb_pc,
	input mips_core_pkg::BranchOutcome i_fb_prediction,
	input mips_core_pkg::BranchOutcome i_fb_outcome
);
	localparam INDEX_WIDTH = $clog2(BASE_LEN); 

    logic [1 : 0] prediction_counter [BASE_LEN]; 

	logic [INDEX_WIDTH - 1 : 0] hit_index;
	logic [INDEX_WIDTH - 1 : 0] update_index; 


	assign hit_index = i_req_pc[2 +: INDEX_WIDTH];
	assign update_index = i_fb_pc[2 +: INDEX_WIDTH];

	always_comb
	begin
		o_req_prediction = 0; 
		if (i_req_valid) o_req_prediction = prediction_counter[hit_index][1];
	end

	always_ff @(posedge clk)
	begin
		if(~rst_n)
		begin
			prediction_counter <= '{default: 2'b10};	// Weakly taken
		end
		else
		begin
			if (i_fb_valid)
			begin
				if (i_fb_prediction == i_fb_outcome)
				begin
					if (prediction_counter[update_index] < 2'b11) prediction_counter[update_index] <= prediction_counter[update_index] + 2'b01; 
				end

				else 
				begin
					if (prediction_counter[update_index] > 2'b00) prediction_counter[update_index] <= prediction_counter[update_index] - 2'b01; 
				end
			end
		end
	end

endmodule