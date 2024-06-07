module mmu (
    input   wire logic                      cpu_clk_i,
    input   wire logic                      flush_i,

    input   wire logic [31:0]               satp_i,
    input   wire logic [1:0]                current_priv_icsr_i,
    input   wire logic [1:0]                effective_priv_icsr_i,
    input   wire logic                      mxr, 
    input   wire logic                      sum,

    // Address to translate (combinational interface)
    input   wire logic [31:0]               itlb_virt_addr_i,
    input   wire logic                      itlb_virt_addr_vld_i,
    output  wire logic [31:0]               itlb_translated_addr_o,
    output  wire logic [3:0]                itlb_excp_code_o,
    output  wire logic                      itlb_excp_code_vld_o,
    output  wire logic                      itlb_ans_vld_o,
    // Address to translate (combinational interface)
    input   wire logic [31:0]               dtlb_virt_addr_i,
    input   wire logic                      dtlb_virt_addr_vld_i,
    input   wire logic                      dtlb_isWrite_i,
    output  wire logic [31:0]               dtlb_translated_addr_o,
    output  wire logic [3:0]                dtlb_excp_code_o,
    output  wire logic                      dtlb_excp_code_vld_o,
    output  wire logic                      dtlb_ans_vld_o,
    // MMU management instructions (common)
    input   wire logic                      sfence_i,
    output  wire logic                      sfence_in_prog,
    output  wire logic                      sfence_cmplt_o,
    output  wire logic                      safe_to_flush_o,

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
    output  wire logic                      hpw_d_ready
);

    wire logic [19:0]    itlb_vpn;
    wire logic           itlb_vpn_vld;
    wire logic           itlb_busy; // true on any cycle with any lsu activity
    wire logic           itlb_resp_vld;
    wire logic           itlb_is_superpage;
    wire logic [31:0]    itlb_assoc_pte;
    wire logic [3:0]     itlb_excp_code;
    wire logic           itlb_excp_vld;
    wire logic [19:0]    dtlb_vpn;
    wire logic           dtlb_vpn_vld;
    wire logic           isWrite;
    wire logic           dtlb_busy; // true on any cycle with any lsu activity
    wire logic           dtlb_resp_vld;
    wire logic           dtlb_is_superpage;
    wire logic [31:0]    dtlb_assoc_pte;
    wire logic [3:0]     dtlb_excp_code;
    wire logic           dtlb_excp_vld;
    wire logic           itlb_sfence_in_prog;
    wire logic           itlb_sfence_cmplt_o;
    wire logic           itlb_safe_to_flush_o;
    wire logic           dtlb_sfence_in_prog;
    wire logic           dtlb_sfence_cmplt_o;
    wire logic           dtlb_safe_to_flush_o;
    wire logic           hpw_safe_to_flush;
    assign sfence_in_prog = itlb_sfence_in_prog|dtlb_sfence_in_prog;
    assign sfence_cmplt_o = dtlb_sfence_cmplt_o|itlb_sfence_cmplt_o;
    assign safe_to_flush_o = hpw_safe_to_flush&&dtlb_safe_to_flush_o&&itlb_safe_to_flush_o;
    itlb itlb0 (cpu_clk_i, flush_i, satp_i[31], current_priv_icsr_i, itlb_virt_addr_i, itlb_virt_addr_vld_i, itlb_translated_addr_o, itlb_excp_code_o, itlb_excp_code_vld_o, itlb_ans_vld_o,
    sfence_i, itlb_sfence_in_prog, itlb_sfence_cmplt_o, itlb_safe_to_flush_o,
    itlb_vpn,
    itlb_vpn_vld,
    itlb_busy, // true on any cycle with any lsu activity
    itlb_resp_vld,
    itlb_is_superpage,
    itlb_assoc_pte,
    itlb_excp_code,
    itlb_excp_vld
    );
    dtlb dtlb0 (cpu_clk_i, flush_i, satp_i[31], effective_priv_icsr_i, mxr, sum, dtlb_virt_addr_i, dtlb_virt_addr_vld_i, dtlb_isWrite_i, dtlb_translated_addr_o, dtlb_excp_code_o, dtlb_excp_code_vld_o, dtlb_ans_vld_o,
    sfence_i, dtlb_sfence_in_prog, dtlb_sfence_cmplt_o, dtlb_safe_to_flush_o,
    dtlb_vpn,
    dtlb_vpn_vld,
    isWrite,
    dtlb_busy, // true on any cycle with any lsu activity
    dtlb_resp_vld,
    dtlb_is_superpage,
    dtlb_assoc_pte,
    dtlb_excp_code,
    dtlb_excp_vld
    );
    hpw hpw0 (
        cpu_clk_i, flush_i, satp_i[19:0], hpw_safe_to_flush, itlb_vpn, itlb_vpn_vld, itlb_busy, itlb_resp_vld, itlb_is_superpage, itlb_assoc_pte, itlb_excp_code, itlb_excp_vld,
        dtlb_vpn, dtlb_vpn_vld, isWrite, dtlb_busy, dtlb_resp_vld, dtlb_is_superpage, dtlb_assoc_pte, dtlb_excp_code, dtlb_excp_vld, hpw_a_opcode,
        hpw_a_param,
        hpw_a_size,
        hpw_a_address,
        hpw_a_mask,
        hpw_a_data,
        hpw_a_corrupt,
        hpw_a_valid,
        hpw_a_ready,
        hpw_d_opcode,
        hpw_d_param,
        hpw_d_size,
        hpw_d_denied,
        hpw_d_data,
        hpw_d_corrupt,
        hpw_d_valid,
        hpw_d_ready
    );
endmodule
