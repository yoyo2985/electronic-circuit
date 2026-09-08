//------------------------------------------------------------------------------
// tb_voice_control.v   场景: (owner, cmd帧) → cmd_vote → decision → motion
//   A owner=1+left帧 → LEFT(3), vl=-50/vr=+50
//   B owner=0+left帧 → 无执行(o_cmd_valid 恒 0, 轮速 0)
//   C owner=1+stop帧 → STOP(0), 轮速 0
// 注入层: MFCC(共享 feature_engine 输出)；owner 由上层 utter_vote 提供(此处模拟)。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_voice_control;

    localparam TL = 10 * 13;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [15:0] in_v = 0;
    reg owner = 1'b0;

    wire cmdv;
    wire [1:0] cmdid;
    wire cmd_dec;
    wire [1:0] vote_id;
    wire o_valid;
    wire [2:0] o_action;
    wire m_valid;
    wire signed [7:0] mvl, mvr;

    cmd_matcher #(
        .TPL0("../../data/commands/cmd_stop.mem"),
        .TPL1("../../data/commands/cmd_left.mem"),
        .TPL2("../../data/commands/cmd_right.mem"),
        .TPL3("../../data/commands/cmd_forward.mem"))
    u_cmd (.clk(clk), .rst_n(rst_n), .mfcc_valid(in_valid), .mfcc_data(in_v),
           .cmd_valid(cmdv), .cmd_id(cmdid), .cmd_dist_min());
    cmd_vote #(.VOTE_N(8), .NUM(4)) u_cv (
        .clk(clk), .rst_n(rst_n), .cmd_valid(cmdv), .cmd_id(cmdid),
        .decision_valid(cmd_dec), .cmd_id_out(vote_id), .frames_seen());
    decision_fsm u_dec (
        .clk(clk), .rst_n(rst_n), .in_valid(cmd_dec),
        .in_vad(1'b0), .in_auth(1'b0), .in_dir(2'd0),
        .i_owner_valid(owner), .i_cmd_decision_valid(1'b1), .i_cmd_id(vote_id),
        .action_valid(), .action(),
        .o_cmd_valid(o_valid), .o_cmd_action(o_action));
    motion_plan u_mot (
        .clk(clk), .rst_n(rst_n), .in_valid(o_valid), .action(o_action),
        .out_valid(m_valid), .vl(mvl), .vr(mvr));

    always #10 clk = ~clk;

    reg [15:0] L[0:TL-1];
    reg [15:0] S[0:TL-1];
    reg [15:0] wbuf[0:TL-1];
    integer i, saw, err;
    reg signed [7:0] ml, mr;

    always @(posedge clk) begin
        if (o_valid) saw = saw + 1;
        if (m_valid) begin ml = mvl; mr = mvr; end
    end

    task feed_buf;
        integer n;
        begin
            for (n = 0; n < TL; n = n + 1) begin
                in_v = $signed(wbuf[n]); in_valid = 1'b1; @(posedge clk);
            end
            in_valid = 1'b0; repeat(40) @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("../../data/scn_left.mem", L);
        $readmemh("../../data/scn_stop.mem", S);
        err = 0; ml = 0; mr = 0;
        rst_n = 1'b0; repeat(4) @(posedge clk); rst_n = 1'b1;

        // A: owner=1 + left
        for (i = 0; i < TL; i = i + 1) wbuf[i] = L[i];
        owner = 1'b1; saw = 0; feed_buf();
        if (saw == 0 || o_action !== 3'd3 || ml !== -8'sd50 || mr !== 8'sd50) begin
            $display("[ERR] A saw=%0d act=%0d vl=%0d vr=%0d want 3,-50,50", saw, o_action, ml, mr);
            err = err + 1;
        end

        // B: owner=0 + left（陌生人不执行）
        rst_n = 1'b0; repeat(2) @(posedge clk); rst_n = 1'b1;
        for (i = 0; i < TL; i = i + 1) wbuf[i] = L[i];
        owner = 1'b0; saw = 0; ml = 0; mr = 0; feed_buf();
        if (saw !== 0) begin
            $display("[ERR] B saw=%0d (expect 0)", saw); err = err + 1;
        end
        if (ml !== 0 || mr !== 0) begin
            $display("[ERR] B motion %0d/%0d (expect 0)", ml, mr); err = err + 1;
        end

        // C: owner=1 + stop
        rst_n = 1'b0; repeat(2) @(posedge clk); rst_n = 1'b1;
        for (i = 0; i < TL; i = i + 1) wbuf[i] = S[i];
        owner = 1'b1; saw = 0; ml = 0; mr = 0; feed_buf();
        if (saw == 0 || o_action !== 3'd0 || ml !== 0 || mr !== 0) begin
            $display("[ERR] C saw=%0d act=%0d vl=%0d vr=%0d want STOP(0),0,0", saw, o_action, ml, mr);
            err = err + 1;
        end

        if (err == 0)
            $display("TEST PASS : A(owner+left->LEFT/-50,+50) B(stranger->no-op) C(owner+stop->STOP/0)");
        else
            $display("TEST FAIL err=%0d", err);
        $finish;
    end

    initial #2000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
