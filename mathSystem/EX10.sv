module EX10 (
    input   wire logic                              cpu_clock_i,
    input   wire logic                              flush_i,

    input   wire logic [17:0]                       data_i,
    input   wire logic                              valid_i,

    output  wire logic [5:0]                        rs1_o,
    output  wire logic [5:0]                        rs2_o,
    input   wire logic [31:0]                       rs1_data_i,
    input   wire logic [31:0]                       rs2_data_i,

    output  wire logic [4:0]                        rob_o,
    // instruction ram
    input   wire logic [3:0]                        opcode_i,
    input   wire logic                              imm_i,
    input   wire logic [31:0]                       immediate_i,
    input   wire logic [5:0]                        dest_i,

    output       logic [31:0]                       alu_a,
    output       logic [31:0]                       alu_b,
    output       logic [3:0]                        alu_opc,
    output       logic [4:0]                        alu_rob_id,
    output       logic [5:0]                        alu_dest,
    output       logic                              alu_valid
);
    assign rob_o = data_i[4:0];
    assign rs1_o = data_i[11:6];
    assign rs2_o = data_i[17:12];
    initial alu_valid = 0;
    always_ff @(posedge cpu_clock_i) begin
        if (valid_i&!flush_i) begin
            alu_a <= rs1_data_i;
            alu_b <= imm_i ? immediate_i :  rs2_data_i;
            alu_opc <= opcode_i;
            alu_rob_id <= data_i[4:0];
            alu_dest <= dest_i;
            alu_valid <= 1;
        end else begin
            alu_valid <= 0;
        end
    end

endmodule
