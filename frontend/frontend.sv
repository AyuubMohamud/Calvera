module frontend #(parameter [31:0] START_ADDR = 32'h00000000) (
    input   wire logic                          cpu_clock_i,
    input   wire logic [1:0]                    current_privlidge,
    input   wire logic                          tw,
    input   wire logic                          tvm,
    input   wire logic                          tsr,
    input   wire logic                          reset_i,
    input   wire logic                          flush_i,
    input   wire logic [31:0]                   flush_address_i,

    output wire logic [31:0]                    virt_addr_o,
    output wire logic                           virt_addr_vld_o,

    input  wire logic [31:0]                    translated_addr_i,
    input  wire logic [3:0]                     excp_code_i,
    input  wire logic                           excp_code_vld_i,
    input  wire logic                           ans_vld_i,

        // System control port
    input   wire logic [1:0]                    scp_op_i,
    // 00 - FLUSH, 01, Toggle ON/OFF, 1x undefined
    input   wire logic                          scp_vld_i,
    output  wire logic                          flush_resp_o,

    // TileLink Bus Master Uncached Heavyweight
    output       logic [2:0]                    icache_a_opcode,
    output       logic [2:0]                    icache_a_param,
    output       logic [3:0]                    icache_a_size,
    output       logic [31:0]                   icache_a_address,
    output       logic [3:0]                    icache_a_mask,
    output       logic [31:0]                   icache_a_data,
    output       logic                          icache_a_corrupt,
    output       logic                          icache_a_valid,
    input   wire logic                          icache_a_ready,

    input   wire logic [2:0]                    icache_d_opcode,
    input   wire logic [1:0]                    icache_d_param,
    input   wire logic [3:0]                    icache_d_size,
    input   wire logic                          icache_d_denied,
    input   wire logic [31:0]                   icache_d_data,
    input   wire logic                          icache_d_corrupt,
    input   wire logic                          icache_d_valid,
    output  wire logic                          icache_d_ready,
    // out to engine
    output       logic                          ins0_port_o,
    output       logic                          ins0_dnagn_o,
    output       logic [4:0]                    ins0_alu_type_o,
    output       logic [3:0]                    ins0_alu_opcode_o,
    output       logic                          ins0_alu_imm_o,
    output       logic [4:0]                    ins0_ios_type_o,
    output       logic [2:0]                    ins0_ios_opcode_o,
    output       logic [4:0]                    ins0_special_o,
    output       logic [4:0]                    ins0_rs1_o,
    output       logic [4:0]                    ins0_rs2_o,
    output       logic [4:0]                    ins0_dest_o,
    output       logic [31:0]                   ins0_imm_o,
    output       logic [2:0]                    ins0_reg_props_o,
    output       logic                          ins0_dnr_o,    
    output       logic                          ins0_mov_elim_o,
    output       logic                          ins0_excp_valid_o,
    output       logic [3:0]                    ins0_excp_code_o,
    output       logic                          ins1_port_o,
    output       logic                          ins1_dnagn_o,
    output       logic [4:0]                    ins1_alu_type_o,
    output       logic [3:0]                    ins1_alu_opcode_o,
    output       logic                          ins1_alu_imm_o,
    output       logic [4:0]                    ins1_ios_type_o,
    output       logic [2:0]                    ins1_ios_opcode_o,
    output       logic [4:0]                    ins1_special_o,
    output       logic [4:0]                    ins1_rs1_o,
    output       logic [4:0]                    ins1_rs2_o,
    output       logic [4:0]                    ins1_dest_o,
    output       logic [31:0]                   ins1_imm_o,
    output       logic [2:0]                    ins1_reg_props_o,
    output       logic                          ins1_dnr_o, 
    output       logic                          ins1_mov_elim_o,
    output       logic                          ins1_excp_valid_o,
    output       logic [3:0]                    ins1_excp_code_o,
    output       logic                          ins1_valid_o,
    output       logic [31:0]                   insbundle_pc_o,
    output       logic [1:0]                    btb_btype_o,
    output       logic [1:0]                    btb_bm_pred_o,
    output       logic [31:0]                   btb_target_o,
    output       logic                          btb_vld_o,
    output       logic                          btb_idx_o,
    output       logic                          btb_way_o,
    output       logic                          valid_o,
    input   wire logic                          rn_busy_i,

    input   wire logic [31:0]                   c1_btb_vpc_i, //! SIP PC
    input   wire logic [31:0]                   c1_btb_target_i, //! SIP Target **if** taken
    input   wire logic [1:0]                    c1_cntr_pred_i, //! Bimodal counter prediction,
    input   wire logic                          c1_bnch_tkn_i, //! Branch taken this cycle
    input   wire logic [1:0]                    c1_bnch_type_i,
    input   wire logic                          c1_bnch_present_i,
    input   wire logic                          c1_btb_mod_i, // ! BTB modify enable
    input   wire logic                          c1_btb_way_i,
    input   wire logic                          c1_btb_bm_i,

    input   wire logic                          mmu_idle
);
    wire logic [31:0]       if1_current_pc_o;
    wire logic              valid_cyc_o;
    wire logic [1:0]        btb_btype_i;
    wire logic [1:0]        btb_bm_pred_i;
    wire logic [31:0]       btb_target_i;
    wire logic              btb_vld_i;
    wire logic              btb_index_i;
    wire logic              btb_way_i;
    wire logic              if2_busy_i;
    wire logic [3:0]        if2_excp_code_o;
    wire logic              if2_excp_vld_o;
    wire logic              if2_vld_o;
    wire logic [31:0]       if2_sip_vpc_o;
    wire logic              if2_btb_index;
    wire logic [1:0]        if2_btype_o;
    wire logic [1:0]        if2_bm_pred_o;
    wire logic [31:0]       if2_btb_target_o;
    wire logic              if2_btb_hit;
    wire logic              if2_btb_way;
    wire logic              btb_correct_f;
    wire logic [31:0]       btb_correct_pc;
    wire flush = flush_i|btb_correct_f;
    wire [31:0] flush_pc = flush_i ? flush_address_i : btb_correct_pc;
    if1 #(START_ADDR) if1stage (cpu_clock_i,reset_i, flush, flush_pc, if1_current_pc_o, valid_cyc_o, btb_btype_i, btb_bm_pred_i, btb_index_i, btb_target_i, btb_vld_i, btb_way_i, 
    if2_busy_i, if2_excp_code_o, if2_excp_vld_o, if2_vld_o, if2_sip_vpc_o, if2_btype_o, if2_bm_pred_o, if2_btb_target_o, if2_btb_index, if2_btb_hit, if2_btb_way);

    btb branchTargetBuffer (cpu_clock_i, flush|reset_i, if1_current_pc_o, valid_cyc_o, btb_btype_i, btb_bm_pred_i, btb_target_i, btb_vld_i, btb_index_i, btb_way_i,
    btb_correct_f,btb_correct_pc,
    c1_btb_vpc_i, c1_btb_target_i, c1_cntr_pred_i, c1_bnch_tkn_i, c1_bnch_type_i, c1_bnch_present_i, c1_btb_mod_i, c1_btb_way_i, c1_btb_bm_i);
    logic                       ic_valid_o;
    logic [31:0]                ic_ppc_o;
    logic [31:0]                ic_sip_vpc_o;
    logic [3:0]                 ic_sip_excp_code_o;
    logic                       ic_sip_excp_vld_o;
    logic                       ic_btb_index_o;
    logic [1:0]                 ic_btb_btype_o;
    logic [1:0]                 ic_btb_bm_pred_o;
    logic [31:0]                ic_btb_target_o;
    logic                       ic_btb_vld_o;
    logic                       ic_btb_way_o;
    logic                       ic_busy_i;
    if2 if2stage (cpu_clock_i, flush|reset_i, if2_sip_vpc_o, if2_excp_code_o, if2_excp_vld_o, if2_btb_index, if2_btype_o, if2_bm_pred_o, if2_btb_target_o, if2_btb_hit, 
    if2_btb_way, if2_vld_o, if2_busy_i, virt_addr_o, virt_addr_vld_o, translated_addr_i, excp_code_i, excp_code_vld_i, ans_vld_i, ic_valid_o,ic_ppc_o,
    ic_sip_vpc_o,ic_sip_excp_code_o,ic_sip_excp_vld_o,ic_btb_index_o,ic_btb_btype_o,ic_btb_bm_pred_o,ic_btb_target_o,ic_btb_vld_o,ic_btb_way_o,ic_busy_i);
    wire logic                      pdc_hit_o;
    wire logic [63:0]               pdc_instruction_o;
    wire logic [31:0]               pdc_sip_vpc_o;
    wire logic [3:0]                pdc_sip_excp_code_o;
    wire logic                      pdc_sip_excp_vld_o;
    wire logic                      pdc_btb_index_o;
    wire logic [1:0]                pdc_btb_btype_o;
    wire logic [1:0]                pdc_btb_bm_pred_o;
    wire logic [31:0]               pdc_btb_target_o;
    wire logic                      pdc_btb_vld_o;
    wire logic                      pdc_btb_way_o;
    wire logic                      pdc_busy_i;
    icache instructionCache (cpu_clock_i, flush|reset_i, ic_valid_o,ic_ppc_o, ic_sip_vpc_o,ic_sip_excp_code_o,ic_sip_excp_vld_o,ic_btb_index_o,ic_btb_btype_o,
    ic_btb_bm_pred_o,ic_btb_target_o,ic_btb_vld_o,ic_btb_way_o,ic_busy_i, pdc_hit_o, pdc_instruction_o, pdc_sip_vpc_o, pdc_sip_excp_code_o, pdc_sip_excp_vld_o, 
    pdc_btb_index_o, pdc_btb_btype_o, pdc_btb_bm_pred_o, pdc_btb_target_o, pdc_btb_vld_o, pdc_btb_way_o, pdc_busy_i, scp_op_i,scp_vld_i,
    flush_resp_o,icache_a_opcode, icache_a_param, icache_a_size, icache_a_address, icache_a_mask, icache_a_data, icache_a_corrupt, icache_a_valid,
    icache_a_ready, icache_d_opcode, icache_d_param, icache_d_size, icache_d_denied, icache_d_data, icache_d_corrupt, icache_d_valid, icache_d_ready);

    predecode predecoder (cpu_clock_i, flush_i|reset_i, current_privlidge, tw, tvm, tsr,  flush_resp_o, mmu_idle,pdc_hit_o,pdc_instruction_o,pdc_sip_vpc_o,pdc_sip_excp_code_o,pdc_sip_excp_vld_o, 
    pdc_btb_index_o,pdc_btb_btype_o,pdc_btb_bm_pred_o,pdc_btb_target_o,pdc_btb_vld_o,pdc_btb_way_o,pdc_busy_i, ins0_port_o,
    ins0_dnagn_o, ins0_alu_type_o, ins0_alu_opcode_o, ins0_alu_imm_o, ins0_ios_type_o, ins0_ios_opcode_o, ins0_special_o, ins0_rs1_o, ins0_rs2_o, ins0_dest_o, ins0_imm_o,
    ins0_reg_props_o, ins0_dnr_o, ins0_mov_elim_o, ins0_excp_valid_o, ins0_excp_code_o, ins1_port_o, ins1_dnagn_o, ins1_alu_type_o, ins1_alu_opcode_o, ins1_alu_imm_o,
    ins1_ios_type_o, ins1_ios_opcode_o, ins1_special_o, ins1_rs1_o, ins1_rs2_o, ins1_dest_o, ins1_imm_o, ins1_reg_props_o, ins1_dnr_o, ins1_mov_elim_o, ins1_excp_valid_o, ins1_excp_code_o, 
    ins1_valid_o, insbundle_pc_o, btb_btype_o, btb_bm_pred_o, btb_target_o, btb_vld_o, btb_idx_o, btb_way_o, valid_o, rn_busy_i, btb_correct_f, btb_correct_pc);
endmodule
