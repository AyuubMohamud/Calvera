module AGU0 (
    input   wire logic                          cpu_clock_i,
    input   wire logic                          flush_i,

    output  wire logic                          lsu_busy_o,
    input   wire logic                          lsu_vld_i,
    input   wire logic [5:0]                    lsu_rob_i,
    input   wire logic [3:0]                    lsu_op_i,
    input   wire logic [31:0]                   lsu_data_i,
    input   wire logic [31:0]                   lsu_addr_i,
    input   wire logic [5:0]                    lsu_dest_i,

    // Address to translate (combinational interface)
    output  wire logic [31:0]                   virt_addr_o,
    output  wire logic                          virt_addr_vld_o,
    output  wire logic                          isWrite_o,

    input   wire logic [31:0]                   translated_addr_i,
    input   wire logic [3:0]                    excp_code_i,
    input   wire logic                          excp_code_vld_i,
    input   wire logic                          ans_vld_i,
    // Load pipe
    input   wire logic                          lq_full_i,
    output       logic [31:0]                   lq_addr_o,
    output       logic [2:0]                    lq_ld_type_o,
    output       logic [5:0]                    lq_dest_o,
    output       logic [5:0]                    lq_rob_o,
    output       logic                          lq_valid_o,
    // store pipe
    input   wire logic                          enqueue_full_i,
    output       logic [29:0]                   enqueue_address_o,
    output       logic [31:0]                   enqueue_data_o,
    output       logic [3:0]                    enqueue_bm_o,
    output       logic                          enqueue_io_o,
    output       logic                          enqueue_en_o,
    output       logic [4:0]                    enqueue_rob_o, 
    output       logic [29:0]                   conflict_address_o,
    output       logic [3:0]                    conflict_bm_o,

    output       logic [31:0]                   excp_pc,
    output       logic                          excp_valid,
    output       logic [3:0]                    excp_code_o,
    output       logic [5:0]                    excp_rob
);
    wire logic                          lsu_vld;
    wire logic [5:0]                    lsu_rob;
    wire logic [3:0]                    lsu_op;
    wire logic [31:0]                   lsu_data;
    wire logic [31:0]                   lsu_addr;
    wire logic [5:0]                    lsu_dest;
    skdbf #(.DW(80)) agu0skidbuffer (cpu_clock_i, flush_i, lq_full_i|enqueue_full_i|(lsu_vld&!ans_vld_i), {lsu_rob,lsu_op,lsu_data,lsu_addr,lsu_dest},
    lsu_vld, lsu_busy_o, {lsu_rob_i, lsu_op_i, lsu_data_i, lsu_addr_i, lsu_dest_i}, lsu_vld_i);
    assign virt_addr_o = lsu_addr;
    assign virt_addr_vld_o = lsu_vld&!flush_i;
    assign isWrite_o = lsu_op[3];
    logic [3:0] bm; logic [31:0] store_data;
    always_comb begin
        case ({lsu_addr[1:0], lsu_op[1:0]})
            4'b0000: begin
                bm = 4'b0001;
                store_data = lsu_data;
            end
            4'b0001: begin
                bm = 4'b0011;
                store_data = lsu_data;
            end
            4'b0010: begin
                bm = 4'b1111;
                store_data = lsu_data;
            end
            4'b0100: begin
                bm = 4'b0010;
                store_data = {16'd0,lsu_data[7:0], 8'd0};
            end
            4'b1000: begin
                bm = 4'b0100;
                store_data = {8'd0,lsu_data[7:0], 16'd0};
            end
            4'b1001: begin
                bm = 4'b1100;
                store_data = {lsu_data[15:0], 16'h0000};
            end
            4'b1100: begin
                bm = 4'b1000; store_data = {lsu_data[7:0], 24'd0};
            end
            default: begin
                bm = 4'b0110; store_data = 0;
            end
        endcase
    end
    wire misaligned = bm==4'b0110;
    always_ff @(posedge cpu_clock_i) begin
        if (!enqueue_full_i&!lq_full_i&lsu_vld) begin
            if (lsu_op[3]&!misaligned) begin
                enqueue_address_o <= translated_addr_i[31:2];
                enqueue_bm_o <= bm;
                enqueue_data_o <= store_data;
                enqueue_io_o <= translated_addr_i[31];
                enqueue_en_o <= ans_vld_i&!excp_code_vld_i;
                enqueue_rob_o <= lsu_rob[4:0];
            end else begin
                enqueue_en_o <= 0;
            end
        end else if (!enqueue_full_i) begin
            enqueue_en_o <= 0;
        end
    end

    always_ff @(posedge cpu_clock_i) begin
        if (!enqueue_full_i&!lq_full_i) begin
            if (!lsu_op[3]&!misaligned) begin
                conflict_address_o <= translated_addr_i[31:2];
                conflict_bm_o <= bm;
            end
        end
    end
    initial lq_valid_o = 0; initial excp_valid = 0; initial enqueue_en_o = 0;
    always_ff @(posedge cpu_clock_i) begin
        if (!enqueue_full_i&!lq_full_i) begin
            lq_addr_o <= translated_addr_i;
            lq_dest_o <= lsu_dest;
            lq_ld_type_o <= lsu_op[2:0];
            lq_rob_o <= lsu_rob;
            lq_valid_o <= !lsu_op[3]&&ans_vld_i&&!excp_code_vld_i&lsu_vld;
        end else if (!lq_full_i) begin
            lq_valid_o <= 0;
        end
    end

    always_ff @(posedge cpu_clock_i) begin
        excp_pc <= translated_addr_i;
        excp_valid <= lsu_vld&&!(enqueue_full_i|lq_full_i)&&ans_vld_i&&excp_code_vld_i;
        excp_rob <= lsu_rob;
        excp_code_o <= excp_code_i;
    end
endmodule
