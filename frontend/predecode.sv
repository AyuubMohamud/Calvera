module predecode (
    input   wire logic                  cpu_clk_i,
    input   wire logic                  flush_i,
    input   wire logic [1:0]            current_privlidge,
    input   wire logic                  tw,
    input   wire logic                  tvm,
    input   wire logic                  tsr,
    input   wire logic                  icache_valid_i,
    input   wire logic [63:0]           instruction_i,
    input   wire logic [31:0]           if2_sip_vpc_i,
    input   wire logic [3:0]            if2_sip_excp_code_i,
    input   wire logic                  if2_sip_excp_vld_i,
    input   wire logic                  if2_btb_index,
    input   wire logic [1:0]            btb_btype_i, //! Branch type: 00 = Cond, 01 = Indirect, 10 - Jump, 11 - Ret
    input   wire logic [1:0]            btb_bm_pred_i, //! Bimodal counter prediction
    input   wire logic [31:0]           btb_target_i, //! Predicted target if branch is taken
    input   wire logic                  btb_vld_i,
    input   wire logic                  btb_way_i,
    output  wire logic                  busy_o,


    output       logic                  ins0_port_o,
    output       logic                  ins0_dnagn_o,
    output       logic [4:0]            ins0_alu_type_o,
    output       logic [3:0]            ins0_alu_opcode_o,
    output       logic                  ins0_alu_imm_o,
    output       logic [4:0]            ins0_ios_type_o,
    output       logic [2:0]            ins0_ios_opcode_o,
    output       logic [4:0]            ins0_special_o,
    output       logic [4:0]            ins0_rs1_o,
    output       logic [4:0]            ins0_rs2_o,
    output       logic [4:0]            ins0_dest_o,
    output       logic [31:0]           ins0_imm_o,
    output       logic [2:0]            ins0_reg_props_o,
    output       logic                  ins0_dnr_o,
    output       logic                  ins0_mov_elim_o,
    output       logic                  ins0_excp_valid_o,
    output       logic [3:0]            ins0_excp_code_o,
    output       logic                  ins1_port_o,
    output       logic                  ins1_dnagn_o,
    output       logic [4:0]            ins1_alu_type_o,
    output       logic [3:0]            ins1_alu_opcode_o,
    output       logic                  ins1_alu_imm_o,
    output       logic [4:0]            ins1_ios_type_o,
    output       logic [2:0]            ins1_ios_opcode_o,
    output       logic [4:0]            ins1_special_o,
    output       logic [4:0]            ins1_rs1_o,
    output       logic [4:0]            ins1_rs2_o,
    output       logic [4:0]            ins1_dest_o,
    output       logic [31:0]           ins1_imm_o,
    output       logic [2:0]            ins1_reg_props_o,
    output       logic                  ins1_dnr_o,
    output       logic                  ins1_mov_elim_o,
    output       logic                  ins1_excp_valid_o,
    output       logic [3:0]            ins1_excp_code_o,
    output       logic                  ins1_valid_o,
    output       logic [31:0]           insbundle_pc_o,
    output       logic [1:0]            btb_btype_o,
    output       logic [1:0]            btb_bm_pred_o,
    output       logic [31:0]           btb_target_o,
    output       logic                  btb_vld_o,
    output       logic                  btb_idx_o,
    output       logic                  btb_way_o,
    output       logic                  valid_o,
    input   wire logic                  rn_busy_i
);
    wire [63:0] rv_instruction_i_p;
    wire [63:0] working_ins;
    wire [31:0] rv_ppc_i;
    wire [31:0] rv_target; wire [1:0] rv_btype; wire [1:0] rv_bm_pred; wire rv_btb_vld; wire excp_vld; wire [3:0] excp_code;
    wire rv_valid; wire btb_idx; wire btb_way;
    skdbf #(.DW(140)) skidbuffer (
        cpu_clk_i, flush_i, rn_busy_i, {working_ins, rv_ppc_i, rv_target, rv_btype, rv_bm_pred, rv_btb_vld, excp_vld, excp_code,btb_idx,btb_way}, rv_valid, busy_o, {instruction_i, if2_sip_vpc_i, btb_target_i, btb_btype_i,
        btb_bm_pred_i, btb_vld_i, if2_sip_excp_vld_i, if2_sip_excp_code_i, if2_btb_index,btb_way_i}, icache_valid_i
    );
    assign rv_instruction_i_p[31:0] = rv_ppc_i[2] ? working_ins[63:32] : working_ins[31:0];
    assign rv_instruction_i_p[63:32] = working_ins[63:32];
    wire [31:0] rv_instruction_i = rv_instruction_i_p[31:0];
    wire [31:0] rv_instruction_i2 = rv_instruction_i_p[63:32];
    wire [31:0] jalrImmediate = {{20{rv_instruction_i[31]}},rv_instruction_i[31:20]};
    wire [31:0] cmpBranchImmediate = {{20{rv_instruction_i[31]}}, rv_instruction_i[7], rv_instruction_i[30:25], rv_instruction_i[11:8], 1'b0};
    wire [31:0] jalImmediate = {{11{rv_instruction_i[31]}}, rv_instruction_i[31], rv_instruction_i[19:12], rv_instruction_i[20], rv_instruction_i[30:21], 1'b0};
    wire [31:0] auipcImmediate = {rv_instruction_i[31:12], 12'h000};
    wire [31:0] storeImmediate = {{20{rv_instruction_i[31]}}, rv_instruction_i[31:25], rv_instruction_i[11:7]};

    // how to do the instructions
    /**
        ALUs and BU require a code in the form of
        ins_type: 0 = ALU, 1 = JAL, 2 = JALR, 3 = LUI, 4 - AUIPC
        opcode: {instruction[30], instruction[14:12]}
        In Order Scheduler: 
        Loads, Stores, CSRx, Fences and Multiply and Divides
        require a code of 
        ins_type : Load, Store, CSR, Fence, MD
        opcode: {signage, size} (LOADs), {0, size} (Stores), {imm, type} (CSR), {instruction[14:12]} (Mults and Divs)
        Special instructions that force the processor to flush
        FENCE.I
        any CSR write
        MRET
        SRET
        SFENCE.VMA
        -- Instruction Attributes
        rs1, rs2, dest, immediate, uses immediate
        reg_alloc, rs1_valid, rs2_valid
        exception_valid, exception_code
    **/
    wire isLoad = rv_instruction_i[6:2]==5'b00000; 
    wire isStore = rv_instruction_i[6:2]==5'b01000;
    wire load_invalid = &rv_instruction_i[14:13]; //11x is invalid given it is load;
    wire store_invalid = rv_instruction_i[14:12] > 3'b010;
    wire isSystem = rv_instruction_i[6:2] == 5'b11100;
    wire isECALL = rv_instruction_i[31:7] == 0;
    wire isSRET = rv_instruction_i[31:7]==25'b0001000000100000000000000;
    wire isMRET = rv_instruction_i[31:7]==25'b0011000000100000000000000;
    wire isWFI =  rv_instruction_i[31:7]==25'b0001000001010000000000000;
    wire isSFENCE_VMA = rv_instruction_i[31:25] == 7'b0001001;
    wire isCSRRW = rv_instruction_i[13:12]==2'b01;
    wire isCSRRS = rv_instruction_i[13:12]==2'b10;
    wire isCSRRC = rv_instruction_i[13:12]==2'b11;
    wire csr_imm = rv_instruction_i[14];
    wire isFenceI = rv_instruction_i[31:0]==32'b00000000000000000001000000001111;
    wire isFence = rv_instruction_i[19:0]==20'b00000000000000001111;
    wire isCmpBranch = rv_instruction_i[6:2] == 5'b11000;
    wire isCMPBranchInvalid = !rv_instruction_i[14]&rv_instruction_i[13]; // 011 and 11x not used
    wire isJAL = rv_instruction_i[6:2]==5'b11011;
    wire isJALR = rv_instruction_i[6:2]==5'b11001;
    wire isAUIPC = rv_instruction_i[6:2]==5'b00101;
    wire isLUI = rv_instruction_i[6:2]==5'b01101;
    wire isOP = rv_instruction_i[6:2]==5'b01100;
    wire isOPIMM = rv_instruction_i[6:2]==5'b00100;
    wire sys_invalid = !(isECALL|isSRET|isMRET|isWFI|isSFENCE_VMA|isCSRRW|isCSRRC|isCSRRS);
    wire invalid_instruction = !(&rv_instruction_i[1:0])||!(isAUIPC|isLUI|(isOP)|(isOPIMM)|isJAL|isJALR|(isCmpBranch&!isCMPBranchInvalid)|(isLoad&!load_invalid)|(isStore&!store_invalid)
    |(isSystem&!sys_invalid)|isFence|isFenceI);
    // second instruction
    wire isLoad2 = rv_instruction_i2[6:2]==5'b00000; 
    wire isStore2 = rv_instruction_i2[6:2]==5'b01000;
    wire load_invalid2 = &rv_instruction_i2[14:13]; //11x is invalid given it is load;
    wire store_invalid2 = rv_instruction_i2[14:12] > 3'b010;
    wire isSystem2 = rv_instruction_i2[6:2] == 5'b11100;
    wire isECALL2 = rv_instruction_i2[31:7] == 0;
    wire isSRET2 = rv_instruction_i2[31:7]==25'b0001000000100000000000000;
    wire isMRET2 = rv_instruction_i2[31:7]==25'b0011000000100000000000000;
    wire isWFI2 =  rv_instruction_i2[31:7]==25'b0001000001010000000000000;
    wire isSFENCE_VMA2 = rv_instruction_i2[31:25] == 7'b0001001;
    wire isCSRRW2 = rv_instruction_i2[13:12]==2'b01;
    wire isCSRRS2 = rv_instruction_i2[13:12]==2'b10;
    wire isCSRRC2 = rv_instruction_i2[13:12]==2'b11;
    wire csr_imm2 = rv_instruction_i2[14];
    wire isFenceI2 = rv_instruction_i2[31:0]==32'b00000000000000000001000000001111;
    wire isFence2 = rv_instruction_i2[19:0]==20'b00000000000000001111;
    wire isCmpBranch2 = rv_instruction_i2[6:2] == 5'b11000;
    wire isCMPBranchInvalid2 = !rv_instruction_i2[14]&rv_instruction_i2[13]; // 011 and 11x not used
    wire isJAL2 = rv_instruction_i2[6:2]==5'b11011;
    wire isJALR2 = rv_instruction_i2[6:2]==5'b11001;
    wire isAUIPC2 = rv_instruction_i2[6:2]==5'b00101;
    wire isLUI2 = rv_instruction_i2[6:2]==5'b01101;
    wire isOP2 = rv_instruction_i2[6:2]==5'b01100;
    wire isOPIMM2 = rv_instruction_i2[6:2]==5'b00100;
    wire sys_invalid2 = !(isECALL2|isSRET2|isMRET2|isWFI2|isSFENCE_VMA2|isCSRRW2|isCSRRC2|isCSRRS2);
    wire invalid_instruction2 = !(&rv_instruction_i2[1:0])||!(isAUIPC2|isLUI2|(isOP2)|(isOPIMM2)|isJAL2|isJALR2|(isCmpBranch2&!isCMPBranchInvalid2)|(isLoad2&!load_invalid2)|(isStore2&!store_invalid2)
    |(isSystem2&!sys_invalid2)|isFence2|isFenceI2);
    wire [3:0] ecall = {2'b10, current_privlidge};
    wire [31:0] jalrImmediate2 = {{20{rv_instruction_i2[31]}},rv_instruction_i2[31:20]};
    wire [31:0] cmpBranchImmediate2 = {{20{rv_instruction_i2[31]}}, rv_instruction_i2[7], rv_instruction_i2[30:25], rv_instruction_i2[11:8], 1'b0};
    wire [31:0] jalImmediate2 = {{11{rv_instruction_i2[31]}}, rv_instruction_i2[31], rv_instruction_i2[19:12], rv_instruction_i2[20], rv_instruction_i2[30:21], 1'b0};
    wire [31:0] auipcImmediate2 = {rv_instruction_i2[31:12], 12'h000};
    wire [31:0] storeImmediate2 = {{20{rv_instruction_i2[31]}}, rv_instruction_i2[31:25], rv_instruction_i2[11:7]};
    initial valid_o = 0;
    always_ff @(posedge cpu_clk_i) begin
        if (flush_i) begin
            valid_o <= 0;
        end else if (!rn_busy_i&rv_valid) begin
            ins0_port_o <= !(isJAL|isJALR|isAUIPC|isLUI|(((isOP&(rv_instruction_i[31:25]!=7'b0000001))|isOPIMM))|isCmpBranch);
            ins0_dnagn_o <= isFenceI|isSystem&(isSRET|isMRET|isSFENCE_VMA);
            ins0_alu_type_o <= {isAUIPC, isLUI, isJALR, isJAL, ((isOP&(rv_instruction_i[31:25]!=7'b0000001))|isOPIMM)};
            ins0_alu_opcode_o <= {rv_instruction_i[30]&isOP, rv_instruction_i[14:12]};
            ins0_alu_imm_o <= isOPIMM;
            ins0_ios_type_o <= {isLoad, isStore, (isCSRRC|isCSRRS|isCSRRW)&isSystem, isFence, (isOP&(rv_instruction_i[31:25]==7'b0000001))};
            ins0_ios_opcode_o <= {rv_instruction_i[14:12]};
            ins0_special_o <= {isFenceI, (isCSRRC|isCSRRS|isCSRRW)&((rv_instruction_i[19:15]!=0)|csr_imm)&isSystem, isMRET&isSystem, isSRET&isSystem, isSFENCE_VMA&isSystem};
            ins0_rs1_o <= rv_instruction_i[19:15];
            ins0_rs2_o <= rv_instruction_i[24:20];
            ins0_dest_o <= rv_instruction_i[11:7];
            ins0_imm_o <= isOPIMM|isJALR|isLoad|isSystem ? jalrImmediate : isStore ? storeImmediate : isLUI|isAUIPC ? auipcImmediate : isJAL ? jalImmediate : isCmpBranch ? cmpBranchImmediate : 0; 
            ins0_reg_props_o <= {(isOP|isOPIMM|isLoad|isJAL|isJALR|isAUIPC|isLUI|((isCSRRW|isCSRRC|isCSRRS)&isSystem))&&(rv_instruction_i[11:7]!=0), !(((isECALL|isSRET|isMRET|isWFI|isSFENCE_VMA)&isSystem)|isAUIPC|isLUI|isJAL), isOP|isCmpBranch|isStore};
            ins0_mov_elim_o <= (rv_instruction_i[31:20]==12'h000)&(rv_instruction_i[14:12]==3'b000)&(rv_instruction_i[6:2]==5'b00100);
            ins1_mov_elim_o <= (rv_instruction_i2[31:20]==12'h000)&(rv_instruction_i2[14:12]==3'b000)&(rv_instruction_i2[6:2]==5'b00100);
            ins0_excp_valid_o <= invalid_instruction|excp_vld|(isSystem&isSRET&(tsr||current_privlidge==2'b00))|
            (isSystem&isSFENCE_VMA&(tvm||current_privlidge<2'b01))|(isSystem&isWFI&(tw||current_privlidge!=2'b11))|(isSystem&isMRET&(current_privlidge!=2'b11));
            ins1_excp_valid_o <= invalid_instruction2|excp_vld|(isSystem2&isSRET2&(tsr||current_privlidge==2'b00))|
            (isSystem2&isSFENCE_VMA2&(tvm||current_privlidge<2'b01))|(isSystem2&isWFI2&(tw||current_privlidge!=2'b11))|(isSystem2&isMRET2&(current_privlidge!=2'b11));
            ins0_excp_code_o <= {excp_vld ? excp_code : isSystem&isECALL ? ecall : 4'b0010};
            ins1_excp_code_o <= excp_vld ? excp_code : isSystem2&isECALL2 ? ecall : 4'b0010;
            ins1_port_o <= !(isJAL2|isJALR2|isAUIPC2|isLUI2|(isOP2&(rv_instruction_i2[31:25]!=7'b0000001))|isOPIMM2|isCmpBranch2);
            ins1_dnagn_o <= isFenceI2|isSystem2&(isSRET2|isMRET2|isSFENCE_VMA2);
            ins1_alu_type_o <= {isAUIPC2, isLUI2, isJALR2, isJAL2, ((isOP2&(rv_instruction_i2[31:25]!=7'b0000001))|isOPIMM2)};
            ins1_alu_opcode_o <= {rv_instruction_i2[30]&isOP2, rv_instruction_i2[14:12]};
            ins1_alu_imm_o <= isOPIMM2;
            ins1_ios_type_o <= {isLoad2, isStore2, (isCSRRC2|isCSRRS2|isCSRRW2)&isSystem2, isFence2, (isOP2)&(rv_instruction_i2[31:25]==7'b0000001)};
            ins1_ios_opcode_o <= {rv_instruction_i2[14:12]};
            ins1_special_o <= {isFenceI2, (isCSRRC2|isCSRRS2|isCSRRW2)&((rv_instruction_i2[19:15]!=0)|csr_imm2)&isSystem2, isMRET2&isSystem2, isSRET2&isSystem2, isSFENCE_VMA2&isSystem2};
            ins1_rs1_o <= rv_instruction_i2[19:15];
            ins1_rs2_o <= rv_instruction_i2[24:20];
            ins1_dest_o <= rv_instruction_i2[11:7];
            ins1_imm_o <= isOPIMM2|isJALR2|isLoad2|isSystem2 ? jalrImmediate2 : isStore2 ? storeImmediate2 : isLUI2|isAUIPC2 ? auipcImmediate2 : isJAL2 ? jalImmediate2 : isCmpBranch2 ? cmpBranchImmediate2 : 0; 
            ins1_reg_props_o <= {(isOP2|isOPIMM2|isLoad2|isJAL2|isJALR2|isAUIPC2|isLUI2|((isCSRRW2|isCSRRC2|isCSRRS2)&isSystem2))&&(rv_instruction_i2[11:7]!=0), !(((isECALL2|isSRET2|isMRET2|isWFI2|isSFENCE_VMA2)&isSystem2)|isAUIPC2|isLUI2|isJAL2), isOP2|isCmpBranch2|isStore2};
            ins1_valid_o <= !rv_ppc_i[2]&!(rv_btb_vld&(rv_target!={rv_ppc_i[31:3], 3'd4})&!btb_idx&(rv_btype[1] ? 1'b1 : rv_bm_pred[1]));
            btb_way_o <= btb_way;
            btb_idx_o <= btb_idx;
            btb_btype_o <= rv_btype;
            btb_bm_pred_o <= rv_bm_pred;
            btb_target_o <= rv_target;
            btb_vld_o <= rv_btb_vld;
            insbundle_pc_o <= rv_ppc_i;
            valid_o <= 1;
            ins0_dnr_o <= isSystem&(isCSRRC|isCSRRW|isCSRRS)&csr_imm;
            ins1_dnr_o <= isSystem&(isCSRRC2|isCSRRW2|isCSRRS2)&csr_imm2;
        end else if (!rn_busy_i&!rv_valid) begin
            valid_o <= 0;
        end
    end
endmodule
