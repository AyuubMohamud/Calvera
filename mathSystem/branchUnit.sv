module branchUnit (
    input   wire logic                      cpu_clock_i,
    input   wire logic                      flush_i,
    // base instruction information
    input   wire logic [31:0]               operand_1,
    input   wire logic [31:0]               operand_2,
    input   wire logic [31:0]               offset,
    input   wire logic [31:0]               pc,
    input   wire logic                      auipc,
    input   wire logic                      lui,
    input   wire logic                      jal,
    input   wire logic                      jalr,
    input   wire logic [2:0]                bnch_cond,
    input   wire logic [5:0]                rob_id_i,
    input   wire logic [5:0]                dest_i,
    // btb info
    input   wire logic  [1:0]               bm_pred_i,
    input   wire logic  [1:0]               btype_i,
    input   wire logic                      btb_vld_i,
    input   wire logic  [31:0]              btb_target_i,
    input   wire logic                      btb_correct_i,
    input   wire logic                      btb_way_i,
    input   wire logic                      valid_i,

    output  logic  [31:0]                   result_o,
    output  logic                           wb_valid_o,
    output  logic  [5:0]                    wb_dest_o,
    output  logic                           res_valid_o,
    output  logic [5:0]                     rob_o,    
    output  logic                           rcu_excp_o,
    output  logic  [31:0]                   c1_btb_vpc_o, //! SIP PC
    output  logic  [31:0]                   c1_btb_target_o, //! SIP Target **if** taken
    output  logic  [1:0]                    c1_cntr_pred_o, //! Bimodal counter prediction,
    output  logic                           c1_bnch_tkn_o, //! Branch taken this cycle
    output  logic  [1:0]                    c1_bnch_type_o,
    output  logic                           c1_bnch_present_o,
    output  logic                           c1_btb_way_o,
    output  logic                           c1_btb_bm_mod_o
);

    wire eq;
    assign eq = operand_1 == operand_2;
    wire gt_30;
    assign gt_30 = operand_1[30:0] > operand_2[30:0];
    logic mts;
    logic mtu;
    always_comb begin
        case ({operand_1[31], operand_2[31], gt_30})
            3'b000: begin
                mts = 0; mtu = 0;
            end
            3'b001: begin
                mts = 1; mtu = 1;
            end
            3'b010: begin
                mts = 1; mtu = 0;
            end
            3'b011: begin
                mts = 1; mtu = 0;
            end
            3'b100: begin
                mts = 0; mtu = 1;
            end
            3'b101: begin
                mts = 0; mtu = 1;
            end
            3'b110: begin
                mts = 1; mtu = 0;
            end
            3'b111: begin
                mts = 0; mtu = 1;
            end
        endcase
    end

    wire mt;
    assign mt = !bnch_cond[1] ? mts : mtu;
    wire lt;
    assign lt = !(mt | eq);

    wire brnch_res;
    assign brnch_res = {bnch_cond[2], bnch_cond[0]} == 2'b00 ? eq :
                       {bnch_cond[2], bnch_cond[0]} == 2'b01 ? !eq : 
                       {bnch_cond[2], bnch_cond[0]} == 2'b10 ? lt :
                       mt|eq; 
    wire [31:0] excp_addr;
    assign excp_addr = btb_correct_i ? pc : jal ? pc+offset : jalr ? operand_1+offset : brnch_res&&!(lui|auipc) ? pc+offset : pc+32'd4;
    wire wrongful_branch = (btb_vld_i&&btb_correct_i);
    wire wrongful_nbranch = !btb_vld_i&&!(lui|auipc);
    wire wrongful_target = btb_target_i!=excp_addr && btb_vld_i;
    wire [1:0] branch_type = jal|jalr ? 2'b10 : 2'b00;
    wire wrongful_type = branch_type!=btype_i && btb_vld_i;
    wire wrongful_bm = (brnch_res^bm_pred_i[1]) && btb_vld_i && branch_type==2'b00;    
    initial rcu_excp_o = 0; initial wb_valid_o = 0; initial res_valid_o = 0;                
    always_ff @(posedge cpu_clock_i) begin
        wb_valid_o <= !flush_i&valid_i&(lui|auipc|jal|jalr)&!(dest_i==0);
        res_valid_o <= !flush_i&valid_i;
        result_o <= lui ? offset : auipc ? offset+pc : pc+4;
        wb_dest_o <= dest_i;
        rob_o <= rob_id_i;
        if ((wrongful_branch|wrongful_nbranch|wrongful_target|wrongful_type|wrongful_bm)&& !flush_i && valid_i) begin
            rcu_excp_o <= 1;
            c1_btb_vpc_o <= pc;
            c1_btb_target_o <= excp_addr; //! SIP Target **if** taken
            c1_cntr_pred_o <= bm_pred_i;  //! Bimodal counter prediction,
            c1_bnch_tkn_o <= (brnch_res|branch_type[1]); //! Branch taken this cycle
            c1_bnch_type_o <= branch_type;
            c1_bnch_present_o <= (brnch_res|branch_type[1])&!btb_correct_i;
        end
        else if (!(wrongful_branch|wrongful_nbranch|wrongful_target|wrongful_type|wrongful_bm) && brnch_res && !flush_i && valid_i) begin
            c1_btb_way_o <= btb_way_i;
            c1_btb_bm_mod_o <= 1;
            c1_btb_vpc_o <= pc;
            rcu_excp_o <= 0;
        end
        else begin
            c1_btb_bm_mod_o <= 0;
            rcu_excp_o <= 0;
        end
    end

endmodule
