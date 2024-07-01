// SPDX-FileCopyrightText: 2023 Ayuub Mohamud <ayuub.mohamud@outlook.com>
// SPDX-License-Identifier: CERN-OHL-W-2.0

//  -----------------------------------------------------------------------------------------
//  | Copyright (C) Ayuub Mohamud 2023.                                                     |
//  |                                                                                       |
//  | This source describes Open Hardware (RTL) and is licensed under the CERN-OHL-W v2.    |
//  |                                                                                       |
//  | You may redistribute and modify this source and make products using it under          |
//  | the terms of the CERN-OHL-W v2 (https://ohwr.org/cern_ohl_w_v2.txt).                  |
//  |                                                                                       |
//  | This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,                   |
//  | INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A                  |
//  | PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.           |
//  |                                                                                       |
//  | Source location: https://github.com/AyuubMohamud/Polaris                              |
//  |                                                                                       |
//  | As per CERN-OHL-W v2 section 4, should You produce hardware based on this             |
//  | source, You must where practicable maintain the Source Location visible               |
//  | in the same manner as is done within this source.                                     |
//  |                                                                                       |
//  -----------------------------------------------------------------------------------------
// Polaris 1st Generation Branch Target Buffer.

module btb (
    input   wire logic                          cpu_clk_i,
    input   wire logic                          reset_i,
    //! IF1 Inputs
    input   wire logic [31:0]                   if1_current_pc_i, //! Current Program counter of IF1 stage
    input   wire logic                          if1_valid,
    output  wire logic [1:0]                    btb_btype_o, //! Branch type: 00 = Cond, 01 = Call, 10 - Jump, 11 - Ret
    output  wire logic [1:0]                    btb_bm_pred_o, //! Bimodal counter prediction
    output  wire logic [31:0]                   btb_target_o, //! Predicted target if branch is taken
    output  wire logic                          btb_vld_o,
    output  wire logic                          btb_index_o,
    output  wire logic                          btb_way_present_o,
    // decode
    input   wire logic                          btb_correct_i,
    input   wire logic [31:0]                   btb_correct_pc,
    // C1 I/O
    input   wire logic [31:0]                   c1_btb_vpc_i, //! SIP PC
    input   wire logic [31:0]                   c1_btb_target_i, //! SIP Target **if** taken
    input   wire logic [1:0]                    c1_cntr_pred_i, //! Bimodal counter prediction,
    input   wire logic                          c1_bnch_tkn_i, //! Branch taken this cycle
    input   wire logic [1:0]                    c1_bnch_type_i,
    input   wire logic                          c1_bnch_present_i,
    input   wire logic                          c1_btb_mod_i, // ! BTB modify enable
    input   wire logic                          c1_btb_way_i,
    input   wire logic                          c1_btb_bm_i
);
    
    reg valid0 [0:31]; reg valid1[0:31]; //! update at only decode time    
    reg [11:0] tag0 [0:31]; reg [11:0] tag1[0:31];//! update at decode time
    reg [1:0] btype [0:63];//! update at decode time
    reg [1:0] bimodal_counters [0:63];//! commit time only update
    reg [29:0] target [0:63]; //! update at decode time or commit time
    reg idx [0:63];
    // If something is being committed at commit time, unless we are talking about the bimodal counters, we have DEFINITELY misprediced something.
    // Hence we can ignore anything coming from the decode unit
    reg random_replacement;
    
    wire [4:0] midx = c1_btb_mod_i ? c1_btb_vpc_i[7:3] : btb_correct_i ? btb_correct_pc[7:3] : if1_current_pc_i[7:3];
    wire [1:0] val_to_be_written;
    assign val_to_be_written = c1_bnch_tkn_i ? (c1_cntr_pred_i == 2'b11 ? 2'b11 : c1_cntr_pred_i + 1'b1) : (c1_cntr_pred_i == 2'b00 ? 2'b00 : c1_cntr_pred_i - 1'b1);
    wire [11:0] hash = c1_btb_mod_i ? (c1_btb_vpc_i[31:20])^(c1_btb_vpc_i[19:8]) : btb_correct_i ? (btb_correct_pc[31:20])^(btb_correct_pc[19:8]) : (if1_current_pc_i[31:20])^(if1_current_pc_i[19:8]);
    wire [1:0] match = {
        tag1[midx]==hash,tag0[midx]==hash
    };
    wire [1:0] valid = {
        valid1[midx], valid0[midx]
    };
    wire [1:0] present = {
        match[1]&valid[1], match[0]&valid[0]
    };
    wire replacement_idx = &valid ? random_replacement : valid[0];
    assign btb_bm_pred_o = bimodal_counters[{~present[0],midx}];
    assign btb_btype_o = btype[ {~present[0], midx}];
    assign btb_target_o = {target[{ ~present[0],midx}], 2'b00};
    assign btb_vld_o = (|present)&!c1_btb_mod_i&!(!btb_index_o&if1_current_pc_i[2]);
    assign btb_index_o = idx[{ ~present[0],midx}];
    assign btb_way_present_o = ~present[0];
    always_ff @(posedge cpu_clk_i) begin
        if (c1_btb_mod_i) begin
            if (|present) begin : modify_entry
                bimodal_counters[{~present[0],midx}] <= c1_bnch_present_i ? val_to_be_written : 0; btype[{~present[0],midx}] <= c1_bnch_type_i; target[{~present[0],midx}] <= c1_btb_target_i[31:2]; // here tags are not changed
                valid0[midx] <= present[0] ?  c1_bnch_present_i : valid0[midx];valid1[midx] <= present[1] ?  c1_bnch_present_i : valid1[midx];
                idx[{~present[0], midx}] <= c1_btb_vpc_i[2];
            end else begin : add_new_entry
                bimodal_counters[{replacement_idx,midx}] <=  c1_bnch_present_i ? val_to_be_written : 0; btype[{replacement_idx,midx}] <= c1_bnch_type_i; target[{replacement_idx,midx}] <= c1_btb_target_i[31:2];
                valid0[{midx}] <= replacement_idx==0 ? c1_bnch_present_i : valid0[midx]; valid1[{midx}] <= replacement_idx==1 ? c1_bnch_present_i : valid1[midx];
                tag0[{midx}] <= replacement_idx==0 ? hash : tag0[midx];tag1[{midx}] <= replacement_idx==1 ? hash : tag1[midx];
                idx[{replacement_idx, midx}] <= c1_btb_vpc_i[2];
            end
        end else if (btb_correct_i) begin
            bimodal_counters[{~present[0],midx}] <= c1_bnch_present_i ? val_to_be_written : 0; btype[{~present[0],midx}] <= c1_bnch_type_i; target[{~present[0],midx}] <= c1_btb_target_i[31:2]; // here tags are not changed
            valid0[midx] <= present[0] ?  0 : valid0[midx];valid1[midx] <= present[1] ? 0: valid1[midx];
            idx[{~present[0], midx}] <= 0;
        end else if (c1_btb_bm_i&!reset_i) begin
            bimodal_counters[{c1_btb_way_i,c1_btb_vpc_i[7:3]}] <= val_to_be_written;
        end
        random_replacement <= ~random_replacement;
    end
endmodule
