module tmu #(parameter HARTID = 0) (
    input   wire logic                          cpu_clock_i,
    // CSR Interface
    input   wire logic [31:0]                   tmu_data_i,
    input   wire logic [11:0]                   tmu_address_i,
    input   wire logic [1:0]                    tmu_opcode_i,
    input   wire logic                          tmu_wr_en,
    //  001 - CSRRW, 010 - CSRRS, 011 - CSRRC,
    // 011 - mret, 100 - sret, 101 - take exception, 110 - take interrupt
    input   wire logic                          tmu_valid_i,
    output       logic                          tmu_done_o,
    output       logic                          tmu_excp_o,
    output       logic [31:0]                   tmu_data_o,
    // exception returns
    input   wire logic                          mret,
    input   wire logic                          sret,
    // exception handling    
    input   wire logic                          take_exception,
    input   wire logic                          take_interrupt,
    input   wire logic                          tmu_go_to_S,
    input   wire logic [31:0]                   tmu_epc_i,
    input   wire logic [31:0]                   tmu_mtval_i,
    input   wire logic [3:0]                    tmu_mcause_i,

    input   wire logic                          tmu_msip_i,
    input   wire logic                          tmu_mtip_i,
    input   wire logic                          tmu_meip_i,
    input   wire logic                          tmu_seip_i,
    // Signals for IQ state machine
    output  wire logic [2:0]                    tmu_mip_o,
    output  wire logic [2:0]                    tmu_sip_o,
    output  wire logic                          mie_o,
    output  wire logic                          sie_o,
    output  wire logic [31:0]                   mideleg_o,
    output  wire logic [31:0]                   medeleg_o,
    output  wire logic                          tw,
    output  wire logic                          tvm,
    output  wire logic                          tsr,
    input   wire logic                          inc_commit0,
    input   wire logic                          inc_commit1,
    // IQ/MMU
    output  wire logic [31:0]                   satp_o,
    output  wire logic                          mxr,
    output  wire logic                          sum,
    output  wire logic [1:0]                    real_privilege,
    output  wire logic [1:0]                    effc_privilege,
    output  wire logic [31:0]                   sepc_o,
    output  wire logic [31:0]                   mepc_o,
    output  wire logic [31:0]                   mtvec_o,
    output  wire logic [31:0]                   stvec_o
);
    /*Optimise before even thinking of putting this on an fpga*/
    reg [1:0] current_privilege_mode = 2'b11; // Initially at 2'b11
    reg [31:0] mvendorid = 0; localparam MVENDORID = 12'hF11;
    reg [31:0] marchid = 0; localparam MARCHID = 12'hF12;
    reg [31:0] mimpid = 0; localparam MIMPID = 12'hF13;
    initial mimpid = 32'h43415631; // CAV1
    reg [31:0] mhartid = HARTID; localparam MHARTID = 12'hF14;
    reg [31:0] mconfigptr = 0; localparam MCONFIGPTR = 12'hF15;

    reg [31:0] mstatus = 0; localparam MSTATUS = 12'h300; 
    reg [31:0] misa = 32'h80001101; localparam MISA = 12'h301;
    reg [31:0] medeleg = 0; localparam MEDELEG = 12'h302;
    reg [31:0] mideleg = 0; localparam MIDELEG = 12'h303;
    reg [31:0] mie = 0; localparam MIE = 12'h304;
    reg [31:0] mtvec = 0; localparam MTVEC = 12'h305;
    reg [31:0] mcounteren = 0; localparam MCOUNTEREN = 12'h306;
    reg [31:0] mstatush = 0; localparam MSTATUSH = 12'h310;

    reg [31:0] mscratch = 0; localparam MSCRATCH = 12'h340;
    reg [31:0] mepc = 0; localparam MEPC = 12'h341;
    reg [31:0] mcause = 0; localparam MCAUSE = 12'h342;
    reg [31:0] mtval = 0; localparam MTVAL = 12'h343;
    reg [31:0] mip = 0; localparam MIP = 12'h344;
    assign mie_o = mstatus[3];
    reg [31:0] menvcfg; localparam MENVCFG = 12'h30A;// fences are already implemented as total
    localparam MENVCFGH = 12'h31A; // RO ZERO

    // SSTATUS is derived from MSTATUS
    localparam SSTATUS = 12'h100;
    localparam SIE = 12'h104;
    reg [31:0] stvec = 0; localparam STVEC = 12'h105;
    reg [31:0] scounteren; localparam SCOUNTEREN = 12'h106; initial scounteren = 0;
    // Counters are NOT accessible to user mode software
    reg [31:0] senvcfg = 0; localparam SENVCFG = 12'h10A; 
    reg [31:0] sscratch = 0; localparam SSCRATCH = 12'h140;
    reg [31:0] sepc = 0; localparam SEPC = 12'h141;
    reg [31:0] scause = 0; localparam SCAUSE = 12'h142;
    reg [31:0] stval = 0; localparam STVAL = 12'h143;
    localparam SIP = 12'h144;
    reg [31:0] satp = 0; localparam SATP = 12'h180;

    // USER accessible CSRs
    reg [63:0] cycle = 0; localparam CYCLE = 12'hC00; localparam CYCLEH = 12'hC80; localparam MCYCLE = 12'hB00; localparam MCYCLEH = 12'hB80;
    reg [63:0] instret = 0; localparam INSTRET = 12'hC01; localparam INSTRETH = 12'hC81;localparam MINSTRET = 12'hB02; localparam MINSTRETH = 12'hB82;
    reg [31:0] mcountinhibit = 0; localparam MCOUNTERINHIBIT = 12'h320; 

    // Vendor-specific CSRs

    assign mideleg_o = mideleg;
    assign medeleg_o = medeleg;
    assign mxr = mstatus[19];
    assign sum = mstatus[18];
    assign real_privilege = current_privilege_mode;
    assign effc_privilege = mstatus[17]&&current_privilege_mode==2'b11 ? mstatus[12:11] : real_privilege;
    assign tmu_mip_o = {tmu_meip_i, tmu_mtip_i, tmu_msip_i}&{mie[11], mie[7], mie[3]};
    assign tmu_sip_o = {tmu_seip_i|mip[9], mip[5], mip[1]}&{mie[9], mie[5], mie[1]};
    assign satp_o = satp;
    assign sie_o = mstatus[1];
    assign tvm = mstatus[20];
    assign tw = mstatus[21];
    assign tsr = mstatus[22];
    logic [31:0] read_data; logic exists;
    always_comb begin
        case (tmu_address_i)
            MVENDORID: begin read_data = mvendorid; exists = 1; end
            MIMPID: begin read_data = mimpid;exists = 1; end
            MARCHID: begin read_data = marchid;exists = 1; end
            MHARTID: begin read_data = mhartid;exists = 1; end
            MCONFIGPTR: begin read_data = mconfigptr;exists = 1; end
            MSTATUS: begin read_data = mstatus;exists = 1; end
            MISA: begin read_data = misa;exists = 1; end
            MIE: begin read_data = mie;exists = 1; end
            MIP: begin read_data = mip;exists = 1;end
            MTVEC: begin read_data = mtvec;exists = 1;end
            MTVAL: begin read_data = mtval;exists = 1;end
            MSTATUSH: begin read_data = mstatush;exists = 1;end
            MCAUSE: begin read_data = mcause;exists = 1;end
            MSCRATCH: begin read_data = mscratch;exists = 1;end
            MEPC: begin read_data = mepc;exists = 1;end
            MCOUNTERINHIBIT: begin read_data = mcountinhibit;exists = 1;end
            MIDELEG: begin read_data = mideleg;exists = 1;end
            MEDELEG: begin read_data = medeleg;exists = 1;end
            MCYCLE: begin read_data = cycle[31:0];exists = 1;end
            MCYCLEH: begin read_data = cycle[63:32];exists = 1;end
            MINSTRET: begin read_data = instret[31:0];exists = 1;end
            MINSTRETH: begin read_data = instret[63:32];exists = 1;end
            MCOUNTEREN: begin read_data = mcounteren; exists = 1; end
            SSTATUS: begin read_data = mstatus& 32'h000DE762;exists = 1;end
            SIE: begin read_data = {22'h0, mie[9], 3'b000, mie[5], 3'b000, mie[1:0]};exists = 1;end
            STVEC: begin read_data = stvec;exists = 1;end
            SCOUNTEREN: begin read_data = scounteren;exists = 1;end
            SENVCFG: begin read_data = senvcfg;exists = 1;end
            SSCRATCH: begin read_data = sscratch;exists = 1;end
            SEPC: begin read_data = sepc;exists = 1;end
            SCAUSE: begin read_data = scause;exists = 1;end
            STVAL: begin read_data = stval;exists = 1;end
            SIP: begin read_data = {22'h0, mip[9], 3'b000, mip[5], 3'b000, mip[1:0]};exists = 1;end
            SATP: begin read_data = satp;exists = 1;end
            CYCLE: begin read_data = cycle[31:0];exists = 1;end
            CYCLEH: begin read_data = cycle[63:32];exists = 1;end
            INSTRET: begin read_data = instret[31:0];exists = 1;end
            INSTRETH: begin read_data = instret[63:32];exists = 1;end
            default: begin
                read_data = 0; exists = 0;
            end
        endcase
    end
    wire [31:0] bit_sc = 1 << tmu_data_i[4:0];
    wire [31:0] new_data = tmu_opcode_i==2'b01 ? tmu_data_i : tmu_opcode_i==2'b10 ? read_data|bit_sc : read_data&~(bit_sc);
    always_ff @(posedge cpu_clock_i) begin
        if ((mret|sret|take_exception|take_interrupt)) begin
            casez ({mret, sret, take_exception, take_interrupt})
                4'b1000: begin : MRET
                    if (current_privilege_mode==2'b11) begin
                        mstatus[3] <= mstatus[7]; // mpie->mie
                        mstatus[12:11] <= 2'b00; // machine mode is least supported mode
                        current_privilege_mode <= mstatus[12:11];
                        mstatus[7] <= 1;
                        mstatus[17] <= mstatus[17]&(mstatus[12:11]==2'b11); // mprv -> 0 when mpp!=M
                    end
                end
                4'b0100: begin : SRET
                    mstatus[1] <= mstatus[5]; // spie->sie
                    current_privilege_mode <= mstatus[8] ? 2'b01 : 2'b00;
                    mstatus[5] <= 1;
                    mstatus[8] <= 0;
                end
                4'b0001: begin : Interrupt
                    if (!tmu_go_to_S) begin
                        mstatus[7] <= 1'b1;
                        mstatus[12:11] <= current_privilege_mode;
                        mstatus[3] <= 0; // mie
                        mepc<={tmu_epc_i[31:2], 2'b00};
                        mcause<={1'b1, 27'd0, tmu_mcause_i[3:0]};
                        mtval <= 0;
                        current_privilege_mode <= 2'b11;
                    end else begin
                        mstatus[5] <= 1'b1;
                        mstatus[8] <= current_privilege_mode[0];
                        mstatus[1] <= 0;
                        sepc<={tmu_epc_i[31:2], 2'b00};
                        scause<={1'b1, 27'd0, tmu_mcause_i[3:0]};
                        stval <= 0;
                        current_privilege_mode <= 2'b01;
                    end
                end
                4'b0010: begin : Exception
                    if (!tmu_go_to_S) begin
                        mstatus[7] <= mstatus[3];
                        mstatus[12:11] <= current_privilege_mode;
                        mstatus[3] <= 0;
                        mepc<={tmu_epc_i[31:2], 2'b00};
                        mcause<={1'b0, 27'd0, tmu_mcause_i[3:0]};
                        mtval <= tmu_mtval_i;current_privilege_mode <= 2'b11;
                    end else begin
                        mstatus[5] <= mstatus[1];
                        mstatus[8] <= current_privilege_mode[0];
                        mstatus[1] <= 0;
                        sepc<={tmu_epc_i[31:2], 2'b00};
                        scause<={1'b0, 27'd0, tmu_mcause_i[3:0]};
                        stval <= tmu_mtval_i;current_privilege_mode <= 2'b01;
                    end
                end
                default: begin
                    
                end
            endcase
        end else if (tmu_valid_i && tmu_wr_en && (current_privilege_mode==2'b11)) begin
            case (tmu_address_i)
                MSTATUS: begin
                    mstatus[22:17] <= new_data[22:17];
                    mstatus[12:11] <= new_data[12:11];
                    mstatus[8:7] <= new_data[8:7];
                    mstatus[5] <= new_data[5];
                    mstatus[3] <= new_data[3]; mstatus[1] <= new_data[1];
                end
                MCAUSE: begin
                    mcause <= new_data;
                end
                MEPC: begin
                    mepc <= {new_data[31:2], 2'b00};
                end
                MTVAL: begin
                    mtval <= new_data;
                end
                SSTATUS: begin
                    mstatus[19:18] <= new_data[19:18];
                    mstatus[8] <= new_data[8];
                    mstatus[5] <= new_data[5];
                    mstatus[1] <= new_data[1];
                end
                SCAUSE: begin
                    scause <= new_data;
                end
                SEPC: begin
                    sepc <= {new_data[31:2], 2'b00};
                end
                STVAL: begin
                    stval <= new_data;
                end
                default: begin
                    
                end
            endcase
        end else if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b01)) begin
            case (tmu_address_i)
                SSTATUS: begin
                    mstatus[19:18] <= new_data[19:18];
                    mstatus[8] <= new_data[8];
                    mstatus[5] <= new_data[5];
                    mstatus[1] <= new_data[1];
                end
                SCAUSE: begin
                    scause <= new_data;
                end
                SEPC: begin
                    sepc <= new_data;
                end
                STVAL: begin
                    stval <= new_data;
                end
                default: begin
                    
                end
            endcase
        end
    end

    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)) begin
            case (tmu_address_i)
                MISA: begin
                    misa[31:30] <= 2'b01;
                    misa[0] <= 1'b1;
                    misa[8] <= 1'b1;
                    misa[12] <= 1'b1;
                end
                MSCRATCH: begin
                    mscratch <= new_data;
                end
                MSTATUSH: begin
                    mstatush <= 0;
                end
                MTVEC: begin
                    mtvec[31:2] <= new_data[31:2];
                    mtvec[1:0] <= new_data[1:0] == 2'b00 ? 2'b00:
                                  new_data[1:0] == 2'b01 ? 2'b01:
                                  2'b00;
                end
                MIE: begin
                    mie[11] <= new_data[11];
                    mie[7] <=  new_data[7];
                    mie[3] <=  new_data[3];
                    mie[9] <= new_data[9];
                    mie[5] <= new_data[5];
                    mie[1] <= new_data[1];
                end
                MENVCFG: begin
                    menvcfg[0] <= new_data[0];
                end
                MCOUNTERINHIBIT: begin
                    mcountinhibit[2] <= new_data[2];
                    mcountinhibit[0] <= new_data[0];
                end
                MIDELEG: begin
                    mideleg[9] <= new_data[9];
                    mideleg[5] <= new_data[5];
                    mideleg[1] <= new_data[1];
                end
                MEDELEG: begin
                    medeleg[9:0] <= new_data[9:0];
                    medeleg[11:10] <= 0;
                    medeleg[13:12] <= new_data[13:12];
                    medeleg[14] <= 0;
                    medeleg[15] <= new_data[15];
                end
                MCOUNTEREN: begin
                    mcounteren[0] <= new_data[0];
                    mcounteren[2] <= new_data[2];
                end
                STVEC: begin
                    stvec[31:2] <= new_data[31:2];
                    stvec[1:0] <= new_data[1:0] == 2'b00 ? 2'b00:
                                  new_data[1:0] == 2'b01 ? 2'b01:
                                  2'b00;
                end
                SATP: begin
                    satp <= new_data;
                end
                SSCRATCH: begin
                    sscratch <= new_data;
                end
                SIE: begin
                    mie[9] <= new_data[9];
                    mie[5] <= new_data[5];
                    mie[1] <= new_data[1];
                end
                SENVCFG: begin
                    senvcfg[0] <= new_data[0];
                end
                default: begin
                    
                end
            endcase
        end else if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b01)) begin
            case (tmu_address_i)
                STVEC: begin
                    stvec[31:2] <= new_data[31:2];
                    stvec[1:0] <= new_data[1:0] == 2'b00 ? 2'b00:
                                  new_data[1:0] == 2'b11 ? 2'b01:
                                  2'b00;
                end
                SATP: begin
                    satp <= new_data;
                end
                SSCRATCH: begin
                    sscratch <= new_data;
                end
                SIE: begin
                    mie[9] <= new_data[9];
                    mie[5] <= new_data[5];
                    mie[1] <= new_data[1];
                end
                SENVCFG: begin
                    senvcfg[0] <= new_data[0];
                end
                default: begin
                    
                end
            endcase
        end
    end

    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)&&(tmu_address_i==MCYCLE)) begin
            cycle[31:0] <= new_data;
        end 
        else if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)&&(tmu_address_i==MCYCLEH)) begin
            cycle[63:32] <= new_data;
        end else if (!mcountinhibit[0]) begin
            cycle <= cycle + 1;
        end
    end
    wire [63:0] constant = inc_commit0&inc_commit1 ? 64'd2 : 64'd1;
    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)&&(tmu_address_i==MINSTRET)) begin
            instret[31:0] <= new_data;
        end 
        else if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)&&(tmu_address_i==MINSTRETH)) begin
            instret[63:32] <= new_data;
        end else if ((inc_commit0|inc_commit1)&!mcountinhibit[2]) begin
            instret <= instret + constant;
        end
    end
    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode==2'b11)&&tmu_address_i==MIP) begin
            mip[9] <= new_data[9];
            mip[5] <= new_data[5];
            mip[1] <= new_data[1]; // S mode bits are all writable at this level
        end
        else if (tmu_valid_i&&tmu_wr_en&&(current_privilege_mode[0])&&tmu_address_i==SIP) begin
            mip[1] <= new_data[1]; // Only SEIP for this level
        end
    end
    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i) begin
            if ((current_privilege_mode==2'b11)) begin
                case (tmu_address_i)
                    MVENDORID: tmu_data_o <= mvendorid;
                    MIMPID: tmu_data_o <= mimpid;
                    MARCHID: tmu_data_o <= marchid;
                    MHARTID: tmu_data_o <= mhartid;
                    MCONFIGPTR: tmu_data_o <= mconfigptr;
                    MSTATUS: tmu_data_o <= mstatus;
                    MISA: tmu_data_o <= misa;
                    MIE: tmu_data_o <= mie;
                    MIP: tmu_data_o <= {20'h0, tmu_meip_i, 1'b0, mip[9]|tmu_seip_i, 1'b0, tmu_mtip_i, 1'b0, mip[5], 1'b0, tmu_msip_i, 1'b0, mip[1:0]};
                    MTVEC: tmu_data_o <= mtvec;
                    MTVAL: tmu_data_o <= mtval;
                    MSTATUSH: tmu_data_o <= mstatush;
                    MCAUSE: tmu_data_o <= mcause;
                    MSCRATCH: tmu_data_o <= mscratch;
                    MEPC: tmu_data_o <= mepc;
                    MENVCFG: tmu_data_o <= menvcfg;
                    MENVCFGH: tmu_data_o <= 0;
                    MCYCLE: tmu_data_o <= cycle[31:0];
                    MCYCLEH: tmu_data_o <= cycle[63:32];
                    MINSTRET: tmu_data_o <= instret[31:0];
                    MINSTRETH: tmu_data_o <= instret[63:32];
                    CYCLE: tmu_data_o <= cycle[31:0];
                    CYCLEH: tmu_data_o <= cycle[63:32];
                    INSTRET: tmu_data_o <= instret[31:0];
                    INSTRETH: tmu_data_o <= instret[63:32];
                    SSTATUS: tmu_data_o <= {12'h000, mstatus[19:18], 9'h000, mstatus[8], 2'b00, mstatus[5], 3'b000, mstatus[1], 1'b0};
                    SIE: tmu_data_o <= {22'h0, mie[9], 3'b000, mie[5], 3'b000, mie[1:0]};
                    STVEC: tmu_data_o <= stvec;
                    SCOUNTEREN: tmu_data_o <= scounteren;
                    SENVCFG: tmu_data_o <= senvcfg;
                    SSCRATCH: tmu_data_o <= sscratch;
                    SEPC: tmu_data_o <= sepc;
                    SCAUSE: tmu_data_o <= scause;
                    STVAL: tmu_data_o <= stval;
                    SIP: tmu_data_o <= {22'h0, mip[9]|tmu_seip_i, 3'b000, mip[5], 3'b000, mip[1:0]};
                    SATP: tmu_data_o <= satp;
                    default: tmu_data_o <= 0;
                endcase
            end else if (current_privilege_mode==2'b01) begin
                case (tmu_address_i)
                    CYCLE: tmu_data_o <= cycle[31:0];
                    CYCLEH: tmu_data_o <= cycle[63:32];
                    INSTRET: tmu_data_o <= instret[31:0];
                    INSTRETH: tmu_data_o <= instret[63:32];
                    SSTATUS: tmu_data_o <= {12'h000, mstatus[19:18], 9'h000, mstatus[8], 2'b00, mstatus[5], 3'b000, mstatus[1], 1'b0};
                    SIE: tmu_data_o <= {22'h0, mie[9], 3'b000, mie[5], 3'b000, mie[1:0]};
                    STVEC: tmu_data_o <= stvec;
                    SCOUNTEREN: tmu_data_o <= scounteren;
                    SENVCFG: tmu_data_o <= senvcfg;
                    SSCRATCH: tmu_data_o <= sscratch;
                    SEPC: tmu_data_o <= sepc;
                    SCAUSE: tmu_data_o <= scause;
                    STVAL: tmu_data_o <= stval;
                    SIP: tmu_data_o <= {22'h0, mip[9]|tmu_seip_i, 3'b000, mip[5], 3'b000, mip[1:0]};
                    SATP: tmu_data_o <= satp;
                    default: begin
                        tmu_data_o <= 0;
                    end
                endcase
            end else if (current_privilege_mode==2'b00) begin
                case (tmu_address_i)
                    CYCLE: tmu_data_o <= cycle[31:0];
                    CYCLEH: tmu_data_o <= cycle[63:32];
                    INSTRET: tmu_data_o <= instret[31:0];
                    INSTRETH: tmu_data_o <= instret[63:32];
                    default: begin
                        tmu_data_o <= 0;
                    end
                endcase                
            end
        end
    end
    assign mepc_o = mepc; assign sepc_o = sepc; assign mtvec_o = mtvec; assign stvec_o = stvec;
    initial tmu_done_o = 0;
    always_ff @(posedge cpu_clock_i) begin
        if (tmu_valid_i) begin
            tmu_done_o <= 1;
            tmu_excp_o <= ~((exists&&(current_privilege_mode>=tmu_address_i[9:8])&&!(tmu_wr_en&&(&tmu_address_i[11:10]))));
        end
        else begin
            tmu_done_o <= 0;
        end
    end
endmodule
