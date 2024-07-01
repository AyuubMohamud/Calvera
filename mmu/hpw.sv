module hpw (
    input   wire logic                      cpu_clk_i,
    input   wire logic                      flush_i,
    input   wire logic [19:0]               satp_i,
    output  wire logic                      safe_to_flush_o,

    input   wire logic [19:0]               itlb_virt_addr_i,
    input   wire logic                      itlb_virt_addr_vld_i,
    output       logic                      itlb_resp_vld_o,
    output       logic                      itlb_is_superpage_o,
    output       logic [31:0]               itlb_assoc_pte_o,
    output       logic [3:0]                itlb_excp_code_o,
    output       logic                      itlb_excp_vld_o,

    input   wire logic [19:0]               dtlb_virt_addr_i,
    input   wire logic                      dtlb_virt_addr_vld_i,
    input   wire logic                      dtlb_is_write_i,
    output  wire logic                      dtlb_resp_vld_o,
    output  wire logic                      dtlb_is_superpage_o,
    output       logic [31:0]               dtlb_assoc_pte_o,
    output       logic [3:0]                dtlb_excp_code_o,
    output       logic                      dtlb_excp_vld_o,

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
    


    localparam IDLE = 2'b00;
    localparam FETCHPTE = 2'b01;
    localparam RAD = 2'b10;
    localparam FINISH = 2'b11;
    assign hpw_d_ready = 1'b1;
    reg origin = 0;
    reg [1:0] hpw_state = IDLE;
    reg [1:0] level = 0;
    reg [31:0] addr;
    wire [9:0] va_vpn = origin ? level[1] ? itlb_virt_addr_i[19:10] : itlb_virt_addr_i[9:0] : level[1] ? dtlb_virt_addr_i[19:10] : dtlb_virt_addr_i[9:0];

    wire reserved_encoding = hpw_d_data[3:1]==3'b010||hpw_d_data[3:1]==3'b110;
    wire io = addr[31];
    wire leaf_pte = hpw_d_data[1]|hpw_d_data[3];
    wire bad_superpage = |hpw_d_data[19:10] && level!=2'b01 && hpw_d_data[0] & |hpw_d_data[3:1];
    assign safe_to_flush_o = hpw_state==IDLE;
    initial hpw_a_valid = 0;
    assign dtlb_is_superpage_o = level==2'b01;
    assign itlb_is_superpage_o = level==2'b01;
    assign dtlb_resp_vld_o = (!origin)&(hpw_state==FINISH);
    assign itlb_resp_vld_o = (origin)&(hpw_state==FINISH);
    always_ff @(posedge cpu_clk_i) begin
        case (hpw_state)
            IDLE: begin
                if (!flush_i) begin
                    if (dtlb_virt_addr_vld_i) begin
                        addr <= {satp_i, 12'h000};
                        level <= 2'b10;
                        origin <= 1'b0;
                        hpw_state <= FETCHPTE;
                    end else if (itlb_virt_addr_vld_i) begin
                        addr <= {satp_i, 12'h000};
                        level <= 2'b10;
                        origin <= 1'b1;
                        hpw_state <= FETCHPTE;
                    end
                end
            end
            FETCHPTE: begin
                if (level!=2'b00 && !io) begin
                    if (hpw_a_ready) begin
                        hpw_a_valid <= 1; hpw_a_data <= 0; hpw_a_corrupt <= 0; hpw_a_param <= 0; hpw_a_size <= 4'd2; hpw_a_mask <= 0;
                        hpw_a_opcode <= 3'd4;
                        hpw_a_address <= addr + {20'h00000, va_vpn, 2'b00};
                        hpw_state <= RAD;
                    end
                end else begin
                    if (!origin) begin
                        dtlb_excp_code_o <= level==2'b00 ? dtlb_is_write_i ? 4'd15 : 4'd13 : dtlb_is_write_i ? 4'd7 : 4'd5;
                        dtlb_excp_vld_o <= 1;
                    end else begin
                        itlb_excp_code_o <= level==2'b00 ? 4'd12 : 4'd1;
                        itlb_excp_vld_o <= 1;
                    end
                    hpw_state <= FINISH;
                end
            end
            RAD: begin
                hpw_a_valid <= hpw_a_ready ? 0 : hpw_a_valid;
                if (hpw_d_ready&&hpw_d_valid) begin
                    if (origin) begin
                        itlb_excp_vld_o <= bad_superpage|reserved_encoding|((~hpw_d_data[3]|~hpw_d_data[6])&(|hpw_d_data[3:1]))|~hpw_d_data[0];
                        itlb_excp_code_o <=4'd12;
                    end else begin
                        dtlb_excp_code_o <= dtlb_is_write_i ? 4'd15 : 4'd13;    
                        dtlb_excp_vld_o <= bad_superpage|reserved_encoding|((~hpw_d_data[6]|(~hpw_d_data[7]&dtlb_is_write_i))&(|hpw_d_data[3:1]))|~hpw_d_data[0];
                    end
                    addr <= {hpw_d_data[29:10], 12'h000};
                    dtlb_assoc_pte_o <= hpw_d_data;
                    itlb_assoc_pte_o <= hpw_d_data;
                    hpw_state <= leaf_pte||(bad_superpage|reserved_encoding|(origin ? ((~hpw_d_data[3]|~hpw_d_data[6])&(|hpw_d_data[3:1]))|~hpw_d_data[0] : 
                    bad_superpage|reserved_encoding|((~hpw_d_data[6]|(~hpw_d_data[7]&dtlb_is_write_i))&(|hpw_d_data[3:1]))|~hpw_d_data[0])) ? FINISH : FETCHPTE;
                    level <= level - 1'b1;
                end
            end
            FINISH: begin
                hpw_state <= IDLE;
            end
        endcase
    end
endmodule
