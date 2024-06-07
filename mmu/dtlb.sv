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

// 64 entry 4 way Instruction TLB

module dtlb (
    input   wire logic                      cpu_clk_i,
    input   wire logic                      flush_i,
    // input from control unit
    input   wire logic                      satp_active,
    input   wire logic [1:0]                current_priv_icsr_i, // effective privilige and not real one like itlb
    input   wire logic                      mxr, 
    input   wire logic                      sum,

    // Address to translate (combinational interface)
    input   wire logic [31:0]               virt_addr_i,
    input   wire logic                      virt_addr_vld_i,
    input   wire logic                      isWrite_i,

    output  wire logic [31:0]               translated_addr_o,
    output  wire logic [3:0]                excp_code_o,
    output  wire logic                      excp_code_vld_o,
    output  wire logic                      ans_vld_o,

    // MMU management instructions
    input   wire logic                      sfence_i,
    output  logic                           sfence_in_prog,
    output  logic                           sfence_cmplt_o,
    output  wire logic                      safe_to_flush_o,

    // HPW
    output logic [19:0]                     vpn_o,
    output logic                            vpn_vld_o,
    output logic                            isWrite_o,
    input   wire logic                      busy_i, // true on any cycle with any lsu activity

    input   wire logic                      resp_vld_i,
    input   wire logic                      is_superpage_i,
    input   wire logic [31:0]               assoc_pte_i,
    input   wire logic [3:0]                excp_code_i,
    input   wire logic                      excp_vld_i
);
    //! VPN = pc[31:12] -> VPN[3:0] used as indexing function, VPN[19:4] used for tag
    // 282 luts, 40 FFs
    reg [3:0] s_idx;
    reg sfence_full_effect;
    reg [15:0] tag0 [0:15];
    reg [15:0] tag1 [0:15];

    reg valid0 [0:15];
    reg valid1 [0:15];
    initial begin
        for (integer i = 0; i < 64; i++) begin
            valid0[i] = 0; valid1[i] = 0;
        end
    end
    reg superpage0 [0:15];
    reg superpage1 [0:15];

    reg rr;
    reg [19:0] ppn [0:31];
    reg user [0:31];
    reg executable [0:31];
    reg readable [0:31];
    reg writable [0:31];
    wire [19:0] utilised_vpn = virt_addr_i[31:12];
    wire [3:0] idx = utilised_vpn[3:0];
    wire [15:0] tag = utilised_vpn[19:4];

    wire [15:0] tag0_read = tag0[idx];
    wire [15:0] tag1_read = tag1[idx];

    wire [1:0] tag_match_part1 = {
        tag1_read[15:6]==tag[15:6],
        tag0_read[15:6]==tag[15:6]
    };
    wire [1:0] tag_match_part2 = {
        tag1_read[5:0]==tag[5:0],
        tag0_read[5:0]==tag[5:0]
    };
    wire superpage0_rd, superpage1_rd;
    assign superpage0_rd = superpage0[idx];
    assign superpage1_rd = superpage1[idx];
    wire valid0_rd, valid1_rd;
    assign valid0_rd = valid0[idx];
    assign valid1_rd = valid1[idx];
    wire [1:0] total_match = {
        tag_match_part1[1]&valid1_rd&(superpage1_rd|tag_match_part2[1]),
        tag_match_part1[0]&valid0_rd&(superpage0_rd|tag_match_part2[0])
    };
    logic enc_match;    
    wire [19:0] selected_ppn = ppn[{enc_match, idx}];
    wire user_pge = user[{enc_match, idx}];
    wire exec_pge = executable[{enc_match, idx}];
    wire read_pge = readable[{enc_match, idx}];
    wire wrte_pge = writable[{enc_match, idx}];
    wire isSuperpg = enc_match == 1'b0 ? superpage0_rd : superpage1_rd;
    wire [1:0] replaced_way = &{valid1_rd, valid0_rd} ? {rr==1, rr==0} : ~{valid1_rd,valid0_rd};
    always_comb begin
        casez (resp_vld_i ? replaced_way : total_match)
            2'bz1: begin
                enc_match = 1'b0;
            end 
            2'b10: begin
                enc_match = 1'b1;
            end
            default: begin
                enc_match = 1'b0;
            end
        endcase
    end


    assign translated_addr_o = satp_active&&(current_priv_icsr_i<=2'b01) ? {selected_ppn[19:10], isSuperpg ? virt_addr_i[21:12] : selected_ppn[9:0], virt_addr_i[11:0]} : virt_addr_i[31:0];
    assign excp_code_o = !resp_vld_i ? isWrite_i ? 4'd15 : 4'd13 : excp_code_i;
    assign excp_code_vld_o = satp_active&&(current_priv_icsr_i<=2'b01) ? resp_vld_i ? excp_vld_i : !(user_pge ? sum|(current_priv_icsr_i == 2'b00) : current_priv_icsr_i == 2'b01)||(isWrite_i&!wrte_pge)||(mxr?
    !read_pge&!exec_pge : !read_pge) : 1'b0;


    
    reg block = 0;
    localparam IDLE = 2'b00;
    localparam SFENCE = 2'b01;
    localparam HPT_REQ = 2'b10;
    localparam HPT_RESP = 2'b11;
    reg [1:0] STATE = IDLE;
    initial vpn_vld_o = 0;
    assign safe_to_flush_o = STATE==IDLE;
    assign ans_vld_o = ((((((|total_match))|(resp_vld_i&&excp_vld_i))&virt_addr_vld_i)&!(sfence_i|sfence_full_effect))|~(satp_active)||(current_priv_icsr_i==2'b11))&&!block; 
    always_ff @(posedge cpu_clk_i) begin
        rr <= ~rr;
        case (STATE)
            IDLE: begin
                if (flush_i) begin
                    sfence_cmplt_o <= 1'b0;
                    STATE <= IDLE;
                    block <= 0;
                end
                else if (sfence_i&!block) begin
                    STATE <= SFENCE;
                    sfence_full_effect <= 1'b1;
                    sfence_in_prog <= 1'b1;
                end else if (!(|total_match)&virt_addr_vld_i&!(current_priv_icsr_i==2'b11)&&satp_active&!block) begin
                    sfence_cmplt_o <= 1'b0;
                    isWrite_o <= isWrite_i;
                    STATE <= HPT_REQ;
                    vpn_o <= virt_addr_i[31:12];
                end else begin
                    sfence_cmplt_o <= 1'b0;
                    STATE <= IDLE;
                end
            end 
            SFENCE: begin    
                if (s_idx==4'b1111) begin
                    s_idx <= 4'b0000;
                    sfence_full_effect <= 1'b0;
                    sfence_cmplt_o <= 1'b1;
                    sfence_in_prog <= 1'b0;
                    STATE<=IDLE;
                    block <= 1;
                end else begin
                    s_idx <= s_idx + 4'b0001;
                    STATE <= SFENCE;
                end
                valid0[s_idx] <= 0;
                valid1[s_idx] <= 0;
            end
            HPT_REQ: begin
                if (busy_i) begin
                    STATE <= HPT_REQ;
                end
                else begin
                    vpn_vld_o <= 1'b1;
                    STATE <= HPT_RESP;
                end
            end
            HPT_RESP: begin
                vpn_vld_o <= busy_i ? vpn_vld_o : 1'b0;
                if (resp_vld_i&!excp_vld_i) begin
                    valid0[idx] <= replaced_way[0] ? 1'b1 : valid0[idx];
                    valid1[idx] <= replaced_way[1]&!replaced_way[0] ? 1'b1 : valid1[idx];
                    
                    ppn[{enc_match, idx}] <= assoc_pte_i[29:10];
                    user[{enc_match, idx}] <= assoc_pte_i[4];
                    executable[{enc_match, idx}] <= assoc_pte_i[3];
                    writable[{enc_match, idx}] <= assoc_pte_i[2];
                    readable[{enc_match, idx}] <= assoc_pte_i[1];

                    superpage0[idx] <= replaced_way[0] ? is_superpage_i : superpage0[idx];
                    superpage1[idx] <= replaced_way[1]&!replaced_way[0] ? is_superpage_i : superpage1[idx];

                    tag0[idx] <= replaced_way[0] ? virt_addr_i[31:16] : tag0[idx];
                    tag1[idx] <= replaced_way[1]&!replaced_way[0] ? virt_addr_i[31:16] : tag1[idx];
                    STATE <= IDLE;
                end
                else if (excp_vld_i&resp_vld_i) begin
                    STATE <= IDLE;
                end
            end
        endcase
    end
endmodule
