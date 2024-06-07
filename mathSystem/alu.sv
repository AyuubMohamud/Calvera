module alu (
    input   wire logic                      cpu_clock_i,
    input   wire logic                      flush_i,

    input   wire logic [31:0]               a,
    input   wire logic [31:0]               b,
    input   wire logic [3:0]                opc,
    input   wire logic [4:0]                rob_id,
    input   wire logic [5:0]                dest,
    input   wire logic                      valid,

    output       logic [31:0]               result,
    output       logic [4:0]                rob_id_o,
    output       logic                      wb_valid_o,
    output       logic [5:0]                dest_o,
    output       logic                      valid_o
);

    // shifter, default is shift left, to shift right it is op[0] = 1
    wire [31:0] shift_res;
    wire [4:0] shamt;
    assign shamt = b[4:0];
    wire [31:0] shift_operand1;
    
    for (genvar i = 0; i < 32; i++) begin : bit_rev1
        assign shift_operand1[i] = !opc[2] ? a[31-i] : a[i];
    end

    wire [31:0] shift_stage1;
    assign shift_stage1[31] = opc[3] ? a[31] : 1'b0;
    assign shift_stage1[30:0] = shift_operand1[31:1]; 

    wire [31:0] shift_res_stage1;
    assign shift_res_stage1 = shamt[0] ? shift_stage1 : shift_operand1;

    wire [31:0] shift_stage2;
    assign shift_stage2[31:30] =  opc[3] ? {{2{a[31]}}} : 2'b00;
    assign shift_stage2[29:0] = shift_res_stage1[31:2]; 

    wire [31:0] shift_res_stage2;
    assign shift_res_stage2 = shamt[1] ? shift_stage2 : shift_res_stage1;

    wire [31:0] shift_stage3;
    assign shift_stage3[31:28] =  opc[3] ? {{4{a[31]}}} : 4'b00;
    assign shift_stage3[27:0] = shift_res_stage2[31:4]; 

    wire [31:0] shift_res_stage3;
    assign shift_res_stage3 = shamt[2] ? shift_stage3 : shift_res_stage2;

    wire [31:0] shift_stage4;
    assign shift_stage4[31:24] =  opc[3] ? {{8{a[31]}}} : 8'b00;
    assign shift_stage4[23:0] = shift_res_stage3[31:8]; 

    wire [31:0] shift_res_stage4;
    assign shift_res_stage4 = shamt[3] ? shift_stage4 : shift_res_stage3;

    wire [31:0] shift_stage5;
    assign shift_stage5[31:16] =  opc[3] ? {{16{a[31]}}} : 16'b00;
    assign shift_stage5[15:0] = shift_res_stage4[31:16]; 

    wire [31:0] shift_res_stage5;
    assign shift_res_stage5 = shamt[4] ? shift_stage5 : shift_res_stage4;

    for (genvar i = 0; i < 32; i++) begin : bit_rev2
        assign shift_res[i] = !opc[2] ? shift_res_stage5[31-i] : shift_res_stage5[i];
    end

    wire [31:0] addition_result;
    wire [31:0] second_operand = opc[3] ? ~b+1 : b;
    assign addition_result = a + second_operand;

    wire less_than = a[30:0] < b[30:0];
    wire less_than_unsigned = (!a[31]&(b[31]|less_than))|(a[31]&b[31]&less_than);
    wire less_than_signed = (a[31]&!b[31])|((a[31]==b[31])&less_than);
    initial valid_o = 0; initial wb_valid_o = 0;
    always_ff @(posedge cpu_clock_i) begin
        valid_o <= valid&!flush_i;
        wb_valid_o <= valid&!flush_i&(dest!=0);
        dest_o <= dest;
        rob_id_o <= rob_id;
        case (opc[2:0])
            3'b000: result <= addition_result; 
            3'b001: result <= shift_res;
            3'b010: result <= {31'd0, less_than_signed};
            3'b011: result <= {31'd0, less_than_unsigned};
            3'b100: result <= a^b;
            3'b101: result <= shift_res;
            3'b110: result <= a|b;
            3'b111: result <= a&b;
        endcase
    end
endmodule
