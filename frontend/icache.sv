module icache (
    input   wire logic                      cpu_clk_i,
    input   wire logic                      flush_i,

    input   wire logic                      if2_vld_i, //! IF2 valid next cycle
    input   wire logic [31:0]               if2_sip_ppc_i, //! Only used for Cache
    input   wire logic [31:0]               if2_sip_vpc_i,
    input   wire logic [3:0]                if2_sip_excp_code_i,
    input   wire logic                      if2_sip_excp_vld_i,
    input   wire logic                      btb_index_i,
    input   wire logic [1:0]                btb_btype_i, //! Branch type: 00 = Cond, 01 = Indirect, 10 - Jump, 11 - Ret
    input   wire logic [1:0]                btb_bm_pred_i, //! Bimodal counter prediction
    input   wire logic [31:0]               btb_target_i, //! Predicted target if branch is taken
    input   wire logic                      btb_vld_i,
    input   wire logic                      btb_way_i,
    output  wire logic                      busy_o,

    // decode
    output       logic                      hit_o,
    output       logic [63:0]               instruction_o,
    output       logic [31:0]               if2_sip_vpc_o,
    output       logic [3:0]                if2_sip_excp_code_o,
    output       logic                      if2_sip_excp_vld_o,
    output       logic                      btb_index_o,
    output       logic [1:0]                btb_btype_o, //! Branch type: 00 = Cond, 01 = Indirect, 10 - Jump, 11 - Ret
    output       logic [1:0]                btb_bm_pred_o, //! Bimodal counter prediction
    output       logic [31:0]               btb_target_o, //! Predicted target if branch is taken
    output       logic                      btb_vld_o,
    output       logic                      btb_way_o,
    input   wire logic                      busy_i,
    // System control port
    input   wire logic [1:0]                scp_op_i,
    // 00 - FLUSH, 01, Toggle ON/OFF, 1x undefined
    input   wire logic                      scp_vld_i,
    output  wire logic                      flush_resp_o,

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
    /* verilator lint_off UNUSEDSIGNAL */
    input   wire logic [2:0]                icache_d_opcode,
    input   wire logic [1:0]                icache_d_param,
    input   wire logic [3:0]                icache_d_size,
    input   wire logic                      icache_d_denied,
    /* verilator lint_on UNUSEDSIGNAL */
    input   wire logic [31:0]               icache_d_data,
    /* verilator lint_off UNUSEDSIGNAL */
    input   wire logic                      icache_d_corrupt,
    /* verilator lint_on UNUSEDSIGNAL */
    input   wire logic                      icache_d_valid,
    output  wire logic                      icache_d_ready
);
    initial icache_a_valid = 0;
    wire [31:0] working_addr; wire [31:0] working_target; wire [1:0] working_type; wire working_btb_vld; wire [1:0] working_bimodal_prediction;
    wire [31:0] working_vpc; wire [3:0] working_excp; wire working_excp_valid;wire btb_way;
    wire working_valid; wire working_btb_index;
    localparam IDLE = 2'b00;
    localparam MISS_REQ = 2'b01;
    localparam MISS_RESP = 2'b10;
    localparam CFLUSH = 2'b11;
    reg [1:0] cache_fsm = IDLE;
    reg stall = 0;
    skdbf #(.DW(108)) skidbuffer (
        cpu_clk_i, flush_i, busy_i|(cache_fsm!=IDLE)|(cache_fsm==IDLE)&scp_vld_i|stall, {working_addr, working_target, working_type, working_btb_vld, working_bimodal_prediction, working_vpc,
        working_excp, working_excp_valid, working_btb_index, btb_way
    }, working_valid, busy_o, {if2_sip_ppc_i, btb_target_i, btb_btype_i, btb_vld_i, btb_bm_pred_i, if2_sip_vpc_i, if2_sip_excp_code_i, if2_sip_excp_vld_i, btb_index_i, btb_way_i}, if2_vld_i
    );
    reg [19:0] tags0 [0:31]; reg [19:0] tags1 [0:31];// from addr[31:0], addr[31:12] is extracted, and addr[12:7] used for index, addr[6:0] is offset
    reg valid0 [0:31];reg valid1 [0:31]; reg [1:0] rr = 2'b01;
    wire req_not_found;
    

    reg [31:0] missed_address = 0; reg missed_index = 0;
    reg [31:0] missed_target = 0; reg [1:0] missed_type = 0; reg missed_btb_vld = 0; reg [1:0] missed_bimodal_prediction = 0; reg [31:0] missed_vpc = 0;
    reg missed_way = 0;
    assign flush_resp_o = cache_fsm==IDLE;
    assign icache_d_ready = 1'b1;
    reg [4:0] counter = 0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] used_address = stall ? missed_address : working_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [1:0] present = {tags1[used_address[11:7]]==used_address[31:12] && valid1[used_address[11:7]], tags0[used_address[11:7]]==used_address[31:12] && valid0[used_address[11:7]]};
    assign req_not_found = working_valid&!(|present);
    
    initial begin
        for (integer x = 0; x < 64; x++) begin
            tags0[x] = 0;tags1[x] = 0;
        end
        for (integer x = 0; x < 64; x++) begin
            valid0[x] = 0;valid1[x] = 0;
        end
    end
    wire [8:0] ram_addr;
    wire [63:0] ram_data;
    assign instruction_o = ram_data; // When busy_i true, data must be held stable.
    assign ram_addr = stall ? missed_address[11:3] : working_addr[11:3];
    wire [1:0] valids = {valid1[missed_address[11:7]],valid0[missed_address[11:7]]};
    wire replacement = &valids ? rr[1] : valids[1];
    wire rd_en = (cache_fsm==IDLE && !busy_i);
    wire wr_en = cache_fsm==MISS_RESP && icache_d_ready && icache_d_valid & counter[0];
    reg [31:0] buffer = 0;
    wire [9:0] wr_addr;
    assign wr_addr = {replacement, missed_address[11:7] , counter[4:1]};
    braminst sram0 (
        cpu_clk_i, rd_en, {!present[0], ram_addr}, ram_data, wr_en, wr_addr, {icache_d_data, buffer}
    );
    reg block = 0;
    initial hit_o = 0;
    always_ff @(posedge cpu_clk_i) begin
        case (cache_fsm)
            IDLE: begin
                rr <= {rr[0], rr[1]};
                if (flush_i) begin
                    hit_o <= 0;
                    stall <= 0;
                    block <= 0;
                end
                else if (scp_op_i==2'b00&&scp_vld_i&!block) begin
                    cache_fsm <= CFLUSH;
                    hit_o <= 1'b0;
                end
                else if (req_not_found&!busy_i&!working_excp_valid&!stall&!block) begin // during stalls we do not count 
                    cache_fsm <= MISS_REQ;
                    missed_address <= working_addr;
                    missed_bimodal_prediction <= working_bimodal_prediction;
                    missed_btb_vld <= working_btb_vld;
                    missed_target <= working_target;
                    missed_type <= working_type;
                    missed_vpc <= working_vpc;
                    missed_index <= 1'b1;
                    missed_way <= btb_way;
                    hit_o <= 1'b0;
                    stall <= 1;
                end else if (!busy_i&!block) begin
                    if (stall) begin
                        stall <= 0;
                        if2_sip_vpc_o <= missed_vpc;
                        btb_bm_pred_o <= missed_bimodal_prediction;
                        btb_btype_o <= missed_type;
                        btb_target_o <= missed_target;
                        btb_vld_o <= missed_btb_vld;
                        if2_sip_excp_code_o <= working_excp;
                        if2_sip_excp_vld_o <= 0;
                        btb_index_o <= missed_index;
                        btb_way_o <= missed_way;
                        hit_o <= 1;
                    end else if (!stall) begin
                        stall <= 0;
                        if2_sip_vpc_o <= working_vpc;
                        hit_o <= working_valid;
                        btb_bm_pred_o <= working_bimodal_prediction;
                        btb_vld_o <= working_btb_vld;
                        btb_target_o <= working_target;
                        btb_btype_o <= working_type;
                        btb_index_o <= working_btb_index;
                        btb_way_o <= btb_way;
                        if2_sip_excp_code_o <= working_excp;
                        if2_sip_excp_vld_o <= working_excp_valid;
                    end
                end
            end
            MISS_REQ: begin
                rr <= {rr[0], rr[1]};
                icache_a_address <= {missed_address[31:7], 7'h00};
                icache_a_corrupt <= 1'b0;
                icache_a_data <= 32'h00000000;
                icache_a_mask <= 4'd0;
                icache_a_opcode <= 3'd4;
                icache_a_param <= 3'd0;
                icache_a_size <= 4'd7; // 128 byte cache lines
                icache_a_valid <= 1'b1;
                cache_fsm <= MISS_RESP;
            end
            MISS_RESP: begin
                icache_a_valid <= icache_a_ready ? 0 : icache_a_valid;
                if (icache_d_ready&icache_d_valid) begin
                    if (counter==5'b11111) begin
                        counter <= 5'b00000;
                        cache_fsm <= IDLE;
                        tags0[missed_address[11:7]] <= !replacement ? missed_address[31:12] : tags0[missed_address[11:7]];
                        valid0[missed_address[11:7]] <= !replacement ? 1'b1 : valid0[missed_address[11:7]];
                        tags1[missed_address[11:7]] <= replacement ? missed_address[31:12] : tags1[missed_address[11:7]];
                        valid1[missed_address[11:7]] <= replacement ? 1'b1 : valid1[missed_address[11:7]];
                    end else begin
                        counter <= counter + 1'b1;
                    end
                    buffer <= icache_d_data;
                end
            end
            CFLUSH: begin
                rr <= {rr[0], rr[1]};
                if (counter == 5'b11111) begin
                    cache_fsm <= IDLE;
                    valid0[counter] <= 0;valid1[counter] <= 0;
                    counter <= 0;
                    block <= 1;
                end else begin
                    cache_fsm <= CFLUSH;
                    counter <= counter + 1'b1;
                    valid0[counter] <= 1'b0;valid1[counter] <= 1'b0;
                end
            end
        endcase
    end
endmodule
