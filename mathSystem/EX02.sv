module EX02 (
    input   wire logic                              flush_i,

    input   wire logic [31:0]                       alu_result,
    input   wire logic [4:0]                        alu_rob_id_i,
    input   wire logic                              alu_wb_valid_i,
    input   wire logic [5:0]                        alu_dest_i,
    input   wire logic                              alu_valid_i,

    input   wire logic  [31:0]                      brnch_result_i,
    input   wire logic                              brnch_wb_valid_i,
    input   wire logic  [5:0]                       brnch_wb_dest_i,
    input   wire logic                              brnch_res_valid_i,
    input   wire logic [5:0]                        brnch_rob_i,
    input   wire logic                              brnch_rcu_excp_i,
    input   wire logic  [31:0]                      c1_btb_vpc_i,
    input   wire logic  [31:0]                      c1_btb_target_i,
    input   wire logic  [1:0]                       c1_cntr_pred_i,
    input   wire logic                              c1_bnch_tkn_i,
    input   wire logic  [1:0]                       c1_bnch_type_i,
    input   wire logic                              c1_bnch_present_i,
    input   wire logic                              c1_btb_way_i,
    input   wire logic                              c1_btb_bm_mod_i,
    // update bimodal counters here OR tell control unit to correct exec path

    output  wire logic [31:0]                       p0_we_data,
    output  wire logic [5:0]                        p0_we_dest,
    output  wire logic                              p0_wen,

    output  wire logic [5:0]                        excp_rob,
    output  wire logic [4:0]                        excp_code,
    output  wire logic                              excp_valid,
    output  wire logic  [31:0]                      c1_btb_vpc_o,
    output  wire logic  [31:0]                      c1_btb_target_o,
    output  wire logic  [1:0]                       c1_cntr_pred_o,
    output  wire logic                              c1_bnch_tkn_o,
    output  wire logic  [1:0]                       c1_bnch_type_o,
    output  wire logic                              c1_bnch_present_o,
    
    // to the btb
    output  wire logic                              wb_btb_way_o,
    output  wire logic                              wb_btb_bm_mod_o,

    output  wire logic [4:0]                        ins_completed,
    output  wire logic                              ins_cmp_v
);
    
    assign p0_we_data = brnch_wb_valid_i ? brnch_result_i : alu_result;
    assign p0_we_dest = brnch_wb_valid_i ? brnch_wb_dest_i : alu_dest_i;
    assign p0_wen = (brnch_wb_valid_i|alu_wb_valid_i)&!flush_i;
    assign excp_rob = brnch_rob_i; assign excp_code = |c1_btb_target_i[1:0] ? 5'b00000 : 5'b10000; assign excp_valid = brnch_rcu_excp_i;
    assign c1_btb_vpc_o = c1_btb_vpc_i; assign c1_btb_target_o = c1_btb_target_i; assign c1_cntr_pred_o = c1_cntr_pred_i; assign c1_bnch_tkn_o = c1_bnch_tkn_i;
    assign c1_bnch_type_o = c1_bnch_type_i; assign c1_bnch_present_o = c1_bnch_present_i; assign wb_btb_way_o = c1_btb_way_i; assign wb_btb_bm_mod_o = c1_btb_bm_mod_i;
    assign ins_completed = brnch_res_valid_i ? brnch_rob_i[4:0] : alu_rob_id_i;
    assign ins_cmp_v = brnch_res_valid_i|alu_valid_i;
endmodule
