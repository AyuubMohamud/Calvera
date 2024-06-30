module if1 #(parameter [31:0] START_ADDR = 32'h00000000) (
    input   wire logic              cpu_clk_i,
    input   wire logic              reset_i,
    input   wire logic              flush_i,
    input   wire logic [31:0]       flush_pc_i,
    // BPU signals
    output  wire logic [31:0]       if1_current_pc_o,
    output  wire logic              valid_cyc_o,
    input   wire logic [1:0]        btb_btype_i,
    input   wire logic [1:0]        btb_bm_pred_i,
    input   wire logic              btb_index_i,
    input   wire logic [31:0]       btb_target_i,
    input   wire logic              btb_vld_i,
    input   wire logic              btb_way_i,
    input   wire logic              if2_busy_i,
    // IF2 outputs
    output       logic [3:0]        if2_excp_code_o,
    output       logic              if2_excp_vld_o,
    output       logic              if2_vld_o,
    output       logic [31:0]       if2_sip_vpc_o,
    output       logic [1:0]        if2_btype_o,
    output       logic [1:0]        if2_bm_pred_o,
    output       logic [31:0]       if2_btb_target_o,
    output       logic              if2_btb_index,
    output       logic              if2_btb_hit,
    output       logic              if2_btb_way
);
    
    reg [31:0] program_counter = START_ADDR;
    //initial  begin
    //    program_counter = START_ADDR;
    //end
    wire misaligned = program_counter[2];
    wire [31:0] next_pc = btb_vld_i&(btb_btype_i==2'b00 ? btb_bm_pred_i[1] : 1'b1) ? btb_target_i : misaligned ? program_counter + 4 : program_counter + 8;
    assign valid_cyc_o = !if2_busy_i&!flush_i;
    assign if1_current_pc_o = program_counter;
    initial if2_vld_o = 0;
    always_ff @(posedge cpu_clk_i) begin
        if (reset_i) begin
            program_counter <= START_ADDR;
        end
        else if (flush_i) begin
            program_counter <= flush_pc_i;
            if2_vld_o <= 0;
        end else if (!if2_busy_i) begin
            if2_vld_o <= 1;
            program_counter <= next_pc;
            if2_sip_vpc_o <= program_counter;
            if2_excp_code_o <= 0;
            if2_excp_vld_o <= 0;
            if2_btype_o <= btb_btype_i;
            if2_bm_pred_o <= btb_bm_pred_i;
            if2_btb_hit <= btb_vld_i;
            if2_btb_target_o <= btb_target_i;
            if2_btb_index <= btb_index_i;
            if2_btb_way <= btb_way_i;
        end
    end
    // IF1 always valid in the case where no TLB fault can occur.
endmodule
