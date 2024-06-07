module exception_router (
    input   wire logic [1:0]        current_privilege_mode,
    input   wire logic [15:0]       medeleg,
    input   wire logic [3:0]        exception_code,
    output  wire logic [1:0]        new_privilege
);
    wire lkp = medeleg[exception_code];

    // if 1 supervisor if at U or S and M at M, if 0 then M
    assign new_privilege = lkp ? current_privilege_mode==2'b11 ? 2'b11 : 2'b01 : 2'b11;
endmodule
