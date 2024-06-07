module if2 (
    input   wire logic                      cpu_clock_i,
    input   wire logic                      flush_i,
    input   wire logic [31:0]               if2_sip_vpc_i,
    input   wire logic [3:0]                if2_sip_excp_code_i,
    input   wire logic                      if2_sip_excp_vld_i,
    input   wire logic                      btb_index_i,
    input   wire logic [1:0]                btb_btype_i, //! Branch type: 00 = Cond, 01 = Indirect, 10 - Jump, 11 - Ret
    input   wire logic [1:0]                btb_bm_pred_i, //! Bimodal counter prediction
    input   wire logic [31:0]               btb_target_i, //! Predicted target if branch is taken
    input   wire logic                      btb_vld_i,
    input   wire logic                      btb_way_i,
    input   wire logic                      if1_valid_i,
    output  wire logic                      busy_o,

    // Address to translate (combinational interface)
    output wire logic [31:0]               virt_addr_o,
    output wire logic                      virt_addr_vld_o,

    input  wire logic [31:0]               translated_addr_i,
    input  wire logic [3:0]                excp_code_i,
    input  wire logic                      excp_code_vld_i,
    input  wire logic                      ans_vld_i,
    // cache
    output       logic                     valid_o,
    output       logic [31:0]              if2_ppc_o,
    output       logic [31:0]              if2_sip_vpc_o,
    output       logic [3:0]               if2_sip_excp_code_o,
    output       logic                     if2_sip_excp_vld_o,
    output       logic                     btb_index_o,
    output       logic [1:0]               btb_btype_o,
    output       logic [1:0]               btb_bm_pred_o,
    output       logic [31:0]              btb_target_o,
    output       logic                     btb_vld_o,
    output       logic                     btb_way_o,
    input   wire logic                     busy_i
);
    wire working_valid;
    wire [31:0] working_addr; wire [31:0] working_target; wire [1:0] working_type; wire working_btb_vld; wire [1:0] working_bimodal_prediction;
    wire [3:0] working_excp; wire working_excp_valid; wire working_btb_index; wire btb_way;
    skdbf #(.DW(76)) skidbuffer (cpu_clock_i, flush_i, busy_i|(!ans_vld_i&working_valid), {working_addr,
    working_excp, working_excp_valid, working_type,working_bimodal_prediction, working_target, working_btb_vld, working_btb_index, btb_way}, working_valid, busy_o, {if2_sip_vpc_i,
    if2_sip_excp_code_i,
    if2_sip_excp_vld_i,
    btb_btype_i, //! Branch type: 00 = Cond, 01 = Indirect, 10 - Jump, 11 - Ret
    btb_bm_pred_i, //! Bimodal counter prediction
    btb_target_i, //! Predicted target if branch is taken
    btb_vld_i, btb_index_i, btb_way_i}, if1_valid_i);

    assign virt_addr_o = working_addr;
    assign virt_addr_vld_o = working_valid&!flush_i;
    initial valid_o = 0;
    always_ff @(posedge cpu_clock_i) begin
        if (flush_i) begin
            valid_o <= 0;
        end else if (working_valid&ans_vld_i&!busy_i) begin
            if2_ppc_o <= translated_addr_i;
            if2_sip_vpc_o <= working_addr;
            if2_sip_excp_vld_o <= excp_code_vld_i;
            if2_sip_excp_code_o <= excp_code_i;
            btb_btype_o <= working_type;
            btb_bm_pred_o <= working_bimodal_prediction;
            btb_target_o <= working_target;
            btb_vld_o <= working_btb_vld;
            btb_index_o <= working_btb_index;
            btb_way_o <= btb_way;
            valid_o <= 1'b1;
        end else if ((!working_valid|!ans_vld_i)&!busy_i) begin
            valid_o <= 0;
        end
    end

endmodule
