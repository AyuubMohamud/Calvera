module interrupt_router (
    input   wire logic [1:0]        current_privilege_mode,
    input   wire logic              mie,
    input   wire logic              sie,
    input   wire logic [2:0]        mideleg,
    input   wire logic [2:0]        machine_interrupts,
    input   wire logic [2:0]        supervisor_interrupts,

    output  wire logic              int_o,
    output  wire logic [3:0]        int_type,
    output  wire logic [1:0]        new_mode
);
    wire [2:0] delegated_to_S = supervisor_interrupts&mideleg;
    wire [2:0] kept_at_M = supervisor_interrupts&~mideleg;
    
    wire go_to_M = (((current_privilege_mode==2'b11)&&mie) || current_privilege_mode<=2'b01) && ((|machine_interrupts)|(|kept_at_M));
    wire go_to_S = (current_privilege_mode!=2'b11) && ((current_privilege_mode==2'b01&&sie)||(current_privilege_mode==2'b00)) && (|delegated_to_S);

    wire [3:0] enc_kept_at_M = kept_at_M[2] ? 4'd9 :
                               kept_at_M[0] ? 4'd1 :
                               4'd5;
    wire [3:0] enc_delegated_to_S = delegated_to_S[2] ? 4'd9 :
                               delegated_to_S[0] ? 4'd1 :
                               4'd5;

    wire [3:0] enc_M_only = machine_interrupts[2] ? 4'd11 :
                            machine_interrupts[0] ? 4'd3 :
                            4'd7;

    assign int_o = go_to_M|go_to_S;
    assign new_mode = go_to_M ? 2'b11 : 2'b01;
    assign int_type = go_to_M ? |(machine_interrupts) ? enc_M_only : enc_kept_at_M : enc_delegated_to_S;
endmodule
