//------------------------------------------------------------------------------
// tb_top_voice_system.v   端到端(测试注入): owner/命令帧 → 决策 → 目标
//   A owner=1+left → LEFT, target=0
//   B owner=0+left → 无执行(action≠LEFT, target 保持 90)
//   C owner=1+stop → STOP(0), target 保持 90
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top_voice_system;

    localparam TL = 10 * 13;

    reg clk = 1'b0, rst_n = 1'b0;
    reg fev = 1'b0;
    reg signed [15:0] fed = 0;
    reg own = 1'b0;
    reg aud_bclk = 0, aud_lrc = 0, aud_adcdat = 0;

    wire aud_mclk, aud_scl, aud_sda, tx_out;
    wire [7:0] ledw;
    wire own_out;
    wire [1:0] cmd_out;
    wire [2:0] act_out;
    wire [9:0] posw, tgtw;

    top_voice_system #(.TEST(1), .CTL_DIV(4), .VOTE_N(8)) DUT (
        .sys_clk(clk), .sys_rst_n(rst_n),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .aud_mclk(aud_mclk), .aud_scl(aud_scl), .aud_sda(aud_sda),
        .tx(tx_out), .led(ledw),
        .dbg_fe_valid(fev), .dbg_fe_data(fed), .dbg_owner(own),
        .owner_out(own_out), .cmd_id_out(cmd_out), .action_out(act_out),
        .pos_deg(posw), .target_reg(tgtw)
    );

    always #10 clk = ~clk;

    reg [15:0] L[0:TL-1];
    reg [15:0] S[0:TL-1];
    integer n, err;

    initial begin
        $readmemh("../../data/scn_left.mem", L);
        $readmemh("../../data/scn_stop.mem", S);
        err = 0;
        rst_n = 1'b0; repeat(4) @(posedge clk); rst_n = 1'b1;

        // A owner=1 + left
        own = 1'b1;
        for (n = 0; n < TL; n = n + 1) begin fed = $signed(L[n]); fev = 1'b1; @(posedge clk); end
        fev = 1'b0; repeat(50) @(posedge clk);
        if (own_out !== 1'b1 || act_out !== 3'd3 || tgtw !== 10'd0) begin
            $display("[ERR] A own=%b act=%0d tgt=%0d want 1,LEFT,0", own_out, act_out, tgtw); err = err + 1;
        end

        // B owner=0 + left
        rst_n = 1'b0; repeat(3) @(posedge clk); rst_n = 1'b1;
        own = 1'b0;
        for (n = 0; n < TL; n = n + 1) begin fed = $signed(L[n]); fev = 1'b1; @(posedge clk); end
        fev = 1'b0; repeat(50) @(posedge clk);
        if (own_out !== 1'b0 || act_out === 3'd3 || tgtw !== 10'd90) begin
            $display("[ERR] B own=%b act=%0d tgt=%0d want 0,!=LEFT,90", own_out, act_out, tgtw); err = err + 1;
        end

        // C owner=1 + stop
        rst_n = 1'b0; repeat(3) @(posedge clk); rst_n = 1'b1;
        own = 1'b1;
        for (n = 0; n < TL; n = n + 1) begin fed = $signed(S[n]); fev = 1'b1; @(posedge clk); end
        fev = 1'b0; repeat(50) @(posedge clk);
        if (own_out !== 1'b1 || act_out !== 3'd0 || tgtw !== 10'd90) begin
            $display("[ERR] C own=%b act=%0d tgt=%0d want 1,STOP,90", own_out, act_out, tgtw); err = err + 1;
        end

        if (err == 0)
            $display("TEST PASS : A(owner+left->target0) B(stranger->hold90) C(owner+stop->90)");
        else $display("TEST FAIL err=%0d", err);
        $finish;
    end

    initial #2000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
