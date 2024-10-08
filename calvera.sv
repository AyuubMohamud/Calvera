module calvera #(parameter [31:0] START_ADDR = 32'h0, parameter HARTID = 0) (
    input   wire logic                      cpu_clock_i,
    input   wire logic                      cpu_reset_i,
    // TileLink Bus Master Uncached Heavyweight
    output       logic [2:0]                icache_a_opcode,
    output       logic [2:0]                icache_a_param,
    output       logic [3:0]                icache_a_size,
    output       logic [31:0]               icache_a_address,
    output       logic [3:0]                icache_a_mask,
    output       logic [31:0]               icache_a_data,
    output       logic                      icache_a_corrupt,
    output       logic                      icache_a_valid,
    input   wire logic                      icache_a_ready,

    input   wire logic [2:0]                icache_d_opcode,
    input   wire logic [1:0]                icache_d_param,
    input   wire logic [3:0]                icache_d_size,
    input   wire logic                      icache_d_denied,
    input   wire logic [31:0]               icache_d_data,
    input   wire logic                      icache_d_corrupt,
    input   wire logic                      icache_d_valid,
    output  wire logic                      icache_d_ready,

    // TileLink Bus Master Uncached Heavyweight
    output       logic [2:0]                dcache_a_opcode,
    output       logic [2:0]                dcache_a_param,
    output       logic [3:0]                dcache_a_size,
    output       logic [31:0]               dcache_a_address,
    output       logic [3:0]                dcache_a_mask,
    output       logic [31:0]               dcache_a_data,
    output       logic                      dcache_a_corrupt,
    output       logic                      dcache_a_valid,
    input   wire logic                      dcache_a_ready,

    input   wire logic [2:0]                dcache_d_opcode,
    input   wire logic [1:0]                dcache_d_param,
    input   wire logic [3:0]                dcache_d_size,
    input   wire logic                      dcache_d_denied,
    input   wire logic [31:0]               dcache_d_data,
    input   wire logic                      dcache_d_corrupt,
    input   wire logic                      dcache_d_valid,
    output  wire logic                      dcache_d_ready,

    output       logic [2:0]                hpw_a_opcode,
    output       logic [2:0]                hpw_a_param,
    output       logic [3:0]                hpw_a_size,
    output       logic [31:0]               hpw_a_address,
    output       logic [3:0]                hpw_a_mask,
    output       logic [31:0]               hpw_a_data,
    output       logic                      hpw_a_corrupt,
    output       logic                      hpw_a_valid,
    input   wire logic                      hpw_a_ready,

    input   wire logic [2:0]                hpw_d_opcode,
    input   wire logic [1:0]                hpw_d_param,
    input   wire logic [3:0]                hpw_d_size,
    input   wire logic                      hpw_d_denied,
    input   wire logic [31:0]               hpw_d_data,
    input   wire logic                      hpw_d_corrupt,
    input   wire logic                      hpw_d_valid,
    output  wire logic                      hpw_d_ready,
    input   wire logic [2:0]                ext_int_i,
    input   wire logic                      tmu_seip_i
);
wire logic full_flush;
wire logic [31:0]                   tmu_data_i;
wire logic [11:0]                   tmu_address_i;
wire logic [1:0]                    tmu_opcode_i;
wire logic                          tmu_wr_en;
wire logic                          tmu_valid_i;
     logic                          tmu_done_o;
     logic                          tmu_excp_o;
     logic [31:0]                   tmu_data_o;
wire logic                          mret;
wire logic                          sret;
wire logic                          take_exception;
wire logic                          take_interrupt;
wire logic                          tmu_go_to_S;
wire logic [31:0]                   tmu_epc_i;
wire logic [31:0]                   tmu_mtval_i;
wire logic [3:0]                    tmu_mcause_i;
wire logic                          tmu_msip_i = ext_int_i[0];
wire logic                          tmu_mtip_i = ext_int_i[1];
wire logic                          tmu_meip_i = ext_int_i[2];
wire logic [2:0]                    tmu_mip_o;
wire logic [2:0]                    tmu_sip_o;
wire logic                          mie_o;
wire logic                          sie_o;
wire logic [31:0]                   mideleg_o;
wire logic [31:0]                   medeleg_o;
wire logic                          tw;
wire logic                          tvm;
wire logic                          tsr;
wire logic                          inc_commit0;
wire logic                          inc_commit1;
wire logic [31:0]                   satp_o;
wire logic                          mxr;
wire logic                          sum;
wire logic [1:0]                    real_privilege;
wire logic [1:0]                    effc_privilege;
wire logic [31:0]                   sepc_o;
wire logic [31:0]                   mepc_o;
wire logic [31:0]                   mtvec_o;
wire logic [31:0]                   stvec_o;

    csrfile #(.HARTID(HARTID)) csrfile (cpu_clock_i,tmu_data_i,tmu_address_i,tmu_opcode_i,tmu_wr_en,tmu_valid_i,tmu_done_o,tmu_excp_o,tmu_data_o,mret,sret,take_exception,
    take_interrupt,tmu_go_to_S,tmu_epc_i,tmu_mtval_i,tmu_mcause_i,tmu_msip_i,tmu_mtip_i,tmu_meip_i,tmu_seip_i,tmu_mip_o,tmu_sip_o,mie_o,sie_o,mideleg_o,
    medeleg_o,tw,tvm,tsr,inc_commit0,inc_commit1,satp_o,mxr,sum,real_privilege,effc_privilege,sepc_o,mepc_o,mtvec_o,stvec_o);
    wire logic [31:0]               itlb_virt_addr_i;
    wire logic                      itlb_virt_addr_vld_i;
    wire logic [31:0]               itlb_translated_addr_o;
    wire logic [3:0]                itlb_excp_code_o;
    wire logic                      itlb_excp_code_vld_o;
    wire logic                      itlb_ans_vld_o;
    wire logic [31:0]               dtlb_virt_addr_i;
    wire logic                      dtlb_virt_addr_vld_i;
    wire logic                      dtlb_isWrite_i;
    wire logic [31:0]               dtlb_translated_addr_o;
    wire logic [3:0]                dtlb_excp_code_o;
    wire logic                      dtlb_excp_code_vld_o;
    wire logic                      dtlb_ans_vld_o;
    wire logic                      sfence_i;
    wire logic                      sfence_in_prog;
    wire logic                      sfence_cmplt_o;
    wire logic                      safe_to_flush_o;
    mmu mmu0 (cpu_clock_i, full_flush, satp_o,real_privilege,effc_privilege,mxr,sum,itlb_virt_addr_i,itlb_virt_addr_vld_i,itlb_translated_addr_o,
    itlb_excp_code_o,itlb_excp_code_vld_o,itlb_ans_vld_o,dtlb_virt_addr_i,dtlb_virt_addr_vld_i,dtlb_isWrite_i,dtlb_translated_addr_o,dtlb_excp_code_o,dtlb_excp_code_vld_o,
    dtlb_ans_vld_o,sfence_i,sfence_in_prog,sfence_cmplt_o,safe_to_flush_o, hpw_a_opcode, hpw_a_param, hpw_a_size, hpw_a_address, hpw_a_mask, hpw_a_data, hpw_a_corrupt, 
    hpw_a_valid, hpw_a_ready, hpw_d_opcode, hpw_d_param, hpw_d_size, hpw_d_denied, hpw_d_data, hpw_d_corrupt, hpw_d_valid, hpw_d_ready);
    wire [31:0] flush_addr;
    wire icache_flush, icache_idle;
    logic                          ins0_port_o;
    logic                          ins0_dnagn_o;
    logic [4:0]                    ins0_alu_type_o;
    logic [3:0]                    ins0_alu_opcode_o;
    logic                          ins0_alu_imm_o;
    logic [4:0]                    ins0_ios_type_o;
    logic [2:0]                    ins0_ios_opcode_o;
    logic [4:0]                    ins0_special_o;
    logic [4:0]                    ins0_rs1_o;
    logic [4:0]                    ins0_rs2_o;
    logic [4:0]                    ins0_dest_o;
    logic [31:0]                   ins0_imm_o;
    logic [2:0]                    ins0_reg_props_o;
    logic                          ins0_dnr_o;
    logic                          ins0_mov_elim_o;
    logic                          ins0_excp_valid_o;
    logic [3:0]                    ins0_excp_code_o;
    logic                          ins1_port_o;
    logic                          ins1_dnagn_o;
    logic [4:0]                    ins1_alu_type_o;
    logic [3:0]                    ins1_alu_opcode_o;
    logic                          ins1_alu_imm_o;
    logic [4:0]                    ins1_ios_type_o;
    logic [2:0]                    ins1_ios_opcode_o;
    logic [4:0]                    ins1_special_o;
    logic [4:0]                    ins1_rs1_o;
    logic [4:0]                    ins1_rs2_o;
    logic [4:0]                    ins1_dest_o;
    logic [31:0]                   ins1_imm_o;
    logic [2:0]                    ins1_reg_props_o;
    logic                          ins1_dnr_o;
    logic                          ins1_mov_elim_o;
    logic                          ins1_excp_valid_o;
    logic [3:0]                    ins1_excp_code_o;
    logic                          ins1_valid_o;
    logic [31:0]                   insbundle_pc_o;
    logic [1:0]                    btb_btype_o;
    logic [1:0]                    btb_bm_pred_o;
    logic [31:0]                   btb_target_o;
    logic                          btb_vld_o;
    logic                          btb_idx_o;
    logic                          btb_way_o;
    logic                          valid_o;
    wire logic                     rn_busy_i;
    wire logic [31:0]              c1_btb_vpc_i = c1_btb_vpc_o;
    wire logic [31:0]              c1_btb_target_i = c1_btb_target_o;
    wire logic [1:0]               c1_cntr_pred_i = c1_cntr_pred_o;
    wire logic                     c1_bnch_tkn_i = c1_bnch_tkn_o;
    wire logic [1:0]               c1_bnch_type_i = c1_bnch_type_o;
    wire logic                     c1_bnch_present_i = c1_bnch_present_o;
    wire logic                     c1_btb_mod_i = c1_btb_mod_o;
    wire logic                     c1_btb_way_i;
    wire logic                     c1_btb_bm_i;
    frontend #(START_ADDR) frontend0 (cpu_clock_i, real_privilege, tw, tvm, tsr, cpu_reset_i, full_flush, flush_addr, itlb_virt_addr_i,itlb_virt_addr_vld_i,itlb_translated_addr_o,
    itlb_excp_code_o,itlb_excp_code_vld_o,itlb_ans_vld_o, 2'b00, icache_flush, icache_idle, icache_a_opcode,icache_a_param,icache_a_size,icache_a_address,
    icache_a_mask,icache_a_data,icache_a_corrupt,icache_a_valid,icache_a_ready,icache_d_opcode,icache_d_param,icache_d_size,icache_d_denied,icache_d_data,
    icache_d_corrupt,icache_d_valid,icache_d_ready, ins0_port_o, ins0_dnagn_o, ins0_alu_type_o, ins0_alu_opcode_o, ins0_alu_imm_o, ins0_ios_type_o, ins0_ios_opcode_o, 
    ins0_special_o, ins0_rs1_o, ins0_rs2_o, ins0_dest_o, ins0_imm_o, ins0_reg_props_o, ins0_dnr_o, ins0_mov_elim_o, ins0_excp_valid_o, ins0_excp_code_o, 
    ins1_port_o, ins1_dnagn_o, ins1_alu_type_o, ins1_alu_opcode_o, ins1_alu_imm_o, ins1_ios_type_o, ins1_ios_opcode_o, ins1_special_o, ins1_rs1_o, ins1_rs2_o, 
    ins1_dest_o, ins1_imm_o, ins1_reg_props_o, ins1_dnr_o,  ins1_mov_elim_o, ins1_excp_valid_o, ins1_excp_code_o, ins1_valid_o, insbundle_pc_o, btb_btype_o, 
    btb_bm_pred_o, btb_target_o, btb_vld_o, btb_idx_o, btb_way_o, valid_o, rn_busy_i, c1_btb_vpc_i,c1_btb_target_i,c1_cntr_pred_i,c1_bnch_tkn_i,
    c1_bnch_type_i,c1_bnch_present_i,c1_btb_mod_i,c1_btb_way_i,c1_btb_bm_i,safe_to_flush_o);

    wire logic [3:0]                        ms_ins0_opcode_o;
    wire logic [4:0]                        ms_ins0_ins_type;
    wire logic                              ms_ins0_imm_o;
    wire logic [31:0]                       ms_ins0_immediate_o;
    wire logic [5:0]                        ms_ins0_dest_o;
    wire logic                              ms_ins0_valid;
    wire logic [3:0]                        ms_ins1_opcode_o;
    wire logic [4:0]                        ms_ins1_ins_type;
    wire logic                              ms_ins1_imm_o;
    wire logic [31:0]                       ms_ins1_immediate_o;
    wire logic [5:0]                        ms_ins1_dest_o;
    wire logic                              ms_ins1_valid;
    wire logic [3:0]                        ms_pack_id;
    wire logic [31:0]                       ms_rn_pc_o;
    wire logic  [1:0]                       ms_rn_bm_pred_o;
    wire logic  [1:0]                       ms_rn_btype_o;
    wire logic                              ms_rn_btb_vld_o;
    wire logic  [31:0]                      ms_rn_btb_target_o;
    wire logic                              ms_rn_btb_correct_o;
    wire logic                              ms_rn_btb_way_o;
    wire logic                              ms_rn_btb_idx_o;
    wire logic [3:0]                        ms_rn_btb_pack;
    wire logic                              ms_rn_btb_wen;
    wire logic [18:0]                       ms_p0_data_o;
    wire logic                              ms_p0_vld_o;
    wire logic                              ms_p0_rs1_vld_o;
    wire logic                              ms_p0_rs2_vld_o;
    wire logic                              ms_p0_rs1_rdy;
    wire logic                              ms_p0_rs2_rdy;
    wire logic [18:0]                       ms_p1_data_o;
    wire logic                              ms_p1_vld_o;
    wire logic                              ms_p1_rs1_vld_o;
    wire logic                              ms_p1_rs2_vld_o;
    wire logic                              ms_p1_rs1_rdy;
    wire logic                              ms_p1_rs2_rdy;
    wire logic                              ms_p0_busy_i;
    wire logic                              ms_p1_busy_i;
    wire logic                              memSys_renamer_pkt_vld_o;
    wire logic [5:0]                        memSys_pkt0_rs1_o;
    wire logic [5:0]                        memSys_pkt0_rs2_o;
    wire logic [5:0]                        memSys_pkt0_dest_i;
    wire logic [31:0]                       memSys_pkt0_immediate_o;
    wire logic [4:0]                        memSys_pkt0_ios_type_o;
    wire logic [2:0]                        memSys_pkt0_ios_opcode_o;
    wire logic [4:0]                        memSys_pkt0_rob_o;
    wire logic                              memSys_pkt0_vld_o;
    wire logic [5:0]                        memSys_pkt1_rs1_o;
    wire logic [5:0]                        memSys_pkt1_rs2_o;
    wire logic [5:0]                        memSys_pkt1_dest_o;
    wire logic [31:0]                       memSys_pkt1_immediate_o;
    wire logic [4:0]                        memSys_pkt1_ios_type_o;
    wire logic [2:0]                        memSys_pkt1_ios_opcode_o;
    wire logic                              memSys_pkt1_vld_o;
    wire logic                              memSys_full;
    wire logic [4:0]                        alu0_rob_slot_i;
    wire logic                              alu0_rob_complete_i;
    wire logic [4:0]                        alu1_rob_slot_i;
    wire logic                              alu1_rob_complete_i;
    wire logic [4:0]                        agu0_rob_slot_i;
    wire logic                              agu0_rob_complete_i;
    wire logic [4:0]                        ldq_rob_slot_i;
    wire logic                              ldq_rob_complete_i;
    wire logic                              alu0_reg_ready;
    wire logic [5:0]                        alu0_reg_dest;
    wire logic                              alu1_reg_ready;
    wire logic [5:0]                        alu1_reg_dest;
    wire logic                              stb_c0;
    wire logic                              stb_c1;
    wire logic                              alu_excp_i;
    wire logic [4:0]                        alu_excp_code_i;
    wire logic [5:0]                        rob_i;
    wire logic [31:0]                       alu_c1_btb_vpc_i;
    wire logic [31:0]                       alu_c1_btb_target_i;
    wire logic [1:0]                        alu_c1_cntr_pred_i;
    wire logic                              alu_c1_bnch_tkn_i;
    wire logic [1:0]                        alu_c1_bnch_type_i;
    wire logic                              alu_c1_bnch_present_i;
    wire logic [5:0]                        completed_rob_id;
    wire logic [4:0]                        exception_code_i;
    wire logic [31:0]                       exception_addr;
    wire logic                              exception_i;
    wire logic                              mem_lock, rcu_lock, flush;
    wire logic [4:0]                        oldest_instruction;
    wire logic                              rename_flush_o;
    wire logic                              ins_commit0;
    wire logic                              ins_commit1;
    wire logic [31:0]                       c1_btb_vpc_o;
    wire logic [31:0]                       c1_btb_target_o;
    wire logic [1:0]                        c1_cntr_pred_o;
    wire logic                              c1_bnch_tkn_o;
    wire logic [1:0]                        c1_bnch_type_o;
    wire logic                              c1_bnch_present_o;
    wire logic                              c1_btb_mod_o;
    wire logic              p0_we_i;
    wire logic [31:0]       p0_we_data;
    wire logic [5:0]        p0_we_dest;
    wire logic              p1_we_i;
    wire logic [31:0]       p1_we_data;
    wire logic [5:0]        p1_we_dest;
    wire logic              p2_we_i;
    wire logic [31:0]       p2_we_data;
    wire logic [5:0]        p2_we_dest;
    wire logic [5:0]        p0_rd_src;
    logic [31:0]            p0_rd_datas;
    wire logic [5:0]        p1_rd_src;
    logic [31:0]            p1_rd_datas;
    wire logic [5:0]        p2_rd_src;
    logic [31:0]            p2_rd_datas;
    wire logic [5:0]        p3_rd_src;
    logic [31:0]            p3_rd_datas;
    wire logic [5:0]        p4_rd_src;
    logic [31:0]            p4_rd_datas;
    wire logic [5:0]        p5_rd_src;
    logic [31:0]            p5_rd_datas;
    wire logic [5:0]    r4_vec_indx;
    wire logic          r4;
    wire logic [5:0]    r5_vec_indx;
    wire logic          r5;
    wire stb_emp;
    engine calveraEngine (cpu_clock_i, ins0_port_o, ins0_dnagn_o, ins0_alu_type_o, ins0_alu_opcode_o, ins0_alu_imm_o, ins0_ios_type_o, ins0_ios_opcode_o, 
    ins0_special_o, ins0_rs1_o, ins0_rs2_o, ins0_dest_o, ins0_imm_o, ins0_reg_props_o, ins0_dnr_o, ins0_mov_elim_o, ins0_excp_valid_o, ins0_excp_code_o, 
    ins1_port_o, ins1_dnagn_o, ins1_alu_type_o, ins1_alu_opcode_o, ins1_alu_imm_o, ins1_ios_type_o, ins1_ios_opcode_o, ins1_special_o, ins1_rs1_o, ins1_rs2_o, 
    ins1_dest_o, ins1_imm_o, ins1_reg_props_o, ins1_dnr_o,  ins1_mov_elim_o, ins1_excp_valid_o, ins1_excp_code_o, ins1_valid_o, insbundle_pc_o, btb_btype_o, 
    btb_bm_pred_o, btb_target_o, btb_vld_o, btb_idx_o, btb_way_o, valid_o, rn_busy_i,ms_ins0_opcode_o,ms_ins0_ins_type,ms_ins0_imm_o,ms_ins0_immediate_o,ms_ins0_dest_o,
    ms_ins0_valid,ms_ins1_opcode_o,ms_ins1_ins_type,ms_ins1_imm_o,ms_ins1_immediate_o,ms_ins1_dest_o,ms_ins1_valid,ms_pack_id,ms_rn_pc_o,ms_rn_bm_pred_o,ms_rn_btype_o
    ,ms_rn_btb_vld_o,ms_rn_btb_target_o,ms_rn_btb_correct_o,ms_rn_btb_way_o,ms_rn_btb_idx_o,ms_rn_btb_pack,ms_rn_btb_wen,ms_p0_data_o,ms_p0_vld_o,ms_p0_rs1_vld_o,
    ms_p0_rs2_vld_o,ms_p0_rs1_rdy,ms_p0_rs2_rdy,ms_p1_data_o,ms_p1_vld_o,ms_p1_rs1_vld_o,ms_p1_rs2_vld_o,ms_p1_rs1_rdy,ms_p1_rs2_rdy,ms_p0_busy_i,ms_p1_busy_i,
    memSys_renamer_pkt_vld_o,memSys_pkt0_rs1_o,memSys_pkt0_rs2_o,memSys_pkt0_dest_i,memSys_pkt0_immediate_o,memSys_pkt0_ios_type_o,memSys_pkt0_ios_opcode_o,
    memSys_pkt0_rob_o,memSys_pkt0_vld_o,memSys_pkt1_rs1_o,memSys_pkt1_rs2_o,memSys_pkt1_dest_o,memSys_pkt1_immediate_o,memSys_pkt1_ios_type_o,memSys_pkt1_ios_opcode_o,
    memSys_pkt1_vld_o,memSys_full,real_privilege, medeleg_o[15:0], mie_o, sie_o, {mideleg_o[9],mideleg_o[5],mideleg_o[1]}, tmu_mip_o, tmu_sip_o, 
    alu0_rob_slot_i,alu0_rob_complete_i,alu1_rob_slot_i, alu1_rob_complete_i,agu0_rob_slot_i,agu0_rob_complete_i,ldq_rob_slot_i,ldq_rob_complete_i,alu0_reg_ready,alu0_reg_dest,
    alu1_reg_ready,alu1_reg_dest,stb_c0,stb_c1,stb_emp,
    alu_excp_i,alu_excp_code_i,rob_i,alu_c1_btb_vpc_i, alu_c1_btb_target_i,alu_c1_cntr_pred_i,alu_c1_bnch_tkn_i,alu_c1_bnch_type_i,alu_c1_bnch_present_i,
    completed_rob_id,exception_code_i,exception_addr,exception_i, icache_idle, mem_lock, safe_to_flush_o, icache_flush, sfence_i, flush, flush_addr, rcu_lock,
    oldest_instruction,rename_flush_o,ins_commit0,ins_commit1,mret,sret, take_exception,take_interrupt,tmu_go_to_S,tmu_epc_i,tmu_mtval_i,tmu_mcause_i,sepc_o,
    mepc_o,mtvec_o,stvec_o,c1_btb_vpc_o, c1_btb_target_o, c1_cntr_pred_o,c1_bnch_tkn_o,c1_bnch_type_o,c1_bnch_present_o,c1_btb_mod_o,p0_we_i, p0_we_data, p0_we_dest, p1_we_i, 
    p1_we_data, p1_we_dest, p2_we_i, p2_we_data, p2_we_dest, p0_rd_src, p0_rd_datas, p1_rd_src, p1_rd_datas, p2_rd_src, p2_rd_datas, p3_rd_src, p3_rd_datas, p4_rd_src, 
    p4_rd_datas, p5_rd_src, p5_rd_datas,r4_vec_indx, r4, r5_vec_indx, r5);

    mathSystem maths (cpu_clock_i, full_flush, ms_ins0_opcode_o,ms_ins0_ins_type,ms_ins0_imm_o,ms_ins0_immediate_o,ms_ins0_dest_o,ms_ins0_valid,ms_ins1_opcode_o,
    ms_ins1_ins_type,ms_ins1_imm_o,ms_ins1_immediate_o,ms_ins1_dest_o,ms_ins1_valid,ms_pack_id,ms_rn_pc_o,ms_rn_bm_pred_o,ms_rn_btype_o,ms_rn_btb_vld_o
    ,ms_rn_btb_target_o,ms_rn_btb_correct_o,ms_rn_btb_way_o,ms_rn_btb_idx_o,ms_rn_btb_pack,ms_rn_btb_wen,ms_p0_data_o,ms_p0_vld_o,ms_p0_rs1_vld_o,ms_p0_rs2_vld_o,
    ms_p0_rs1_rdy,ms_p0_rs2_rdy,ms_p1_data_o,ms_p1_vld_o,ms_p1_rs1_vld_o,ms_p1_rs2_vld_o,ms_p1_rs1_rdy,ms_p1_rs2_rdy,ms_p0_busy_i,ms_p1_busy_i, p2_we_i, p2_we_dest,
    alu0_rob_complete_i, alu0_rob_slot_i, alu1_rob_complete_i, alu1_rob_slot_i,alu0_reg_ready, alu0_reg_dest, alu1_reg_ready, alu1_reg_dest, p0_we_data, p0_we_dest, 
    p0_we_i, p1_we_data, p1_we_dest, p1_we_i, p0_rd_src,p1_rd_src,p0_rd_datas,p1_rd_datas,p2_rd_src,p3_rd_src,p2_rd_datas,p3_rd_datas, rob_i, alu_excp_code_i, alu_excp_i,
    alu_c1_btb_vpc_i,alu_c1_btb_target_i,alu_c1_cntr_pred_i,alu_c1_bnch_tkn_i,alu_c1_bnch_type_i,alu_c1_bnch_present_i, c1_btb_way_i, c1_btb_bm_i);

    memorySystem memSys (cpu_clock_i, full_flush, memSys_renamer_pkt_vld_o,memSys_pkt0_rs1_o,memSys_pkt0_rs2_o,memSys_pkt0_dest_i,memSys_pkt0_immediate_o,
    memSys_pkt0_ios_type_o,memSys_pkt0_ios_opcode_o,memSys_pkt0_rob_o,memSys_pkt0_vld_o,memSys_pkt1_rs1_o,memSys_pkt1_rs2_o,memSys_pkt1_dest_o,memSys_pkt1_immediate_o,
    memSys_pkt1_ios_type_o,memSys_pkt1_ios_opcode_o,memSys_pkt1_vld_o,memSys_full, p4_rd_datas, p4_rd_src, p5_rd_datas, p5_rd_src, r4_vec_indx,r4,r5_vec_indx,r5,
    tmu_data_i, tmu_address_i, tmu_opcode_i, tmu_wr_en, tmu_valid_i, tmu_done_o, tmu_excp_o, tmu_data_o, rcu_lock, oldest_instruction, mem_lock, agu0_rob_slot_i,
    agu0_rob_complete_i,ldq_rob_slot_i,ldq_rob_complete_i,exception_i, exception_code_i[3:0], completed_rob_id,exception_addr, p2_we_i, p2_we_data, p2_we_dest, 
    dtlb_virt_addr_i,    dtlb_virt_addr_vld_i,    dtlb_isWrite_i,    dtlb_translated_addr_o,    dtlb_excp_code_o,    dtlb_excp_code_vld_o,    dtlb_ans_vld_o,   
    stb_c0, stb_c1, stb_emp, dcache_a_opcode, dcache_a_param, dcache_a_size, dcache_a_address, dcache_a_mask, dcache_a_data, dcache_a_corrupt, dcache_a_valid, dcache_a_ready, 
    dcache_d_opcode, dcache_d_param, dcache_d_size, dcache_d_denied, dcache_d_data, dcache_d_corrupt, dcache_d_valid, dcache_d_ready);
    assign inc_commit0 = ins_commit0; assign inc_commit1 = ins_commit1; assign full_flush = flush|rename_flush_o; assign exception_code_i[4] = 0;
endmodule
