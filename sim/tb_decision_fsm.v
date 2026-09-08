//------------------------------------------------------------------------------
// tb_decision_fsm.v   决策 FSM 精确比对
//   data/dec_vad.mem + dec_auth.mem + dec_dir.mem + dec_exp.mem
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_decision_fsm;

    localparam LEN = 12;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_vad = 0, in_auth = 0;
    reg [1:0] in_dir = 0;
    wire action_valid;
    wire [2:0] action;

    decision_fsm DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_vad(in_vad), .in_auth(in_auth), .in_dir(in_dir),
        .i_owner_valid(1'b0), .i_cmd_decision_valid(1'b0), .i_cmd_id(2'd0),
        .action_valid(action_valid), .action(action)
    );

    always #10 clk = ~clk;

    reg vm[0:LEN-1];
    reg am[0:LEN-1];
    reg [1:0] dm[0:LEN-1];
    reg [2:0] ex[0:LEN-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (action_valid) begin
            if (oc < LEN && action !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] w%0d act=%0d want=%0d", oc, action, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/dec_vad.mem", vm);
        $readmemh("data/dec_auth.mem", am);
        $readmemh("data/dec_dir.mem", dm);
        $readmemh("data/dec_exp.mem", ex);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            in_vad   = vm[i];
            in_auth  = am[i];
            in_dir   = dm[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err == 0 && oc == LEN)
            $display("TEST PASS : %0d decisions exact", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
