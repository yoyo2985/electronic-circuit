//------------------------------------------------------------------------------
// tb_sig_activity.v   验证活动检测：
//   前半段让 sig 频繁翻转 → on 应=1；后半段让 sig 恒0 → on 应=0。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sig_activity;

    localparam W = 4;          // 窗口=4 个 tick
    reg clk = 1'b0, rst_n = 1'b0;
    reg tick_1ms = 1'b0, sig = 1'b0;
    wire on;

    sig_activity #(.WIND_MS(W)) DUT (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms), .sig(sig), .on(on)
    );

    always #10 clk = ~clk;

    // tick：每 40 clk 一次
    reg [6:0] tc;
    always @(posedge clk) begin
        if (!rst_n) begin tc <= 0; tick_1ms <= 1'b0; end
        else begin
            tick_1ms <= 1'b0;
            if (tc == 39) begin tick_1ms <= 1'b1; tc <= 0; end
            else tc <= tc + 1'b1;
        end
    end

    // sig：前段翻转足够久、后段停
    reg [11:0] sc;
    always @(posedge clk) begin
        if (!rst_n) begin sc <= 0; sig <= 1'b0; end
        else if (sc < 2000) begin sc <= sc + 1'b1; sig <= ~sig; end  // 高频翻转
        else sig <= 1'b0;
    end

    integer bad = 0;
    initial begin
        rst_n = 1'b0;
        repeat(6) @(posedge clk);
        rst_n = 1'b1;

        // 等约 8 个窗口（仍在前段翻转期）
        repeat(8 * (40*W + 10)) @(posedge clk);
        if (on != 1'b1) begin
            $display("[ERR] sig toggling but on=%b", on);
            bad = 1;
        end

        // 等 sig 停 + 2 个窗口后应灭（sc 封顶 30 后 sig 恒 0）
        repeat(50 * (40*W)) @(posedge clk);
        if (on != 1'b0) begin
            $display("[ERR] sig idle but on=%b", on);
            bad = 1;
        end

        if (bad == 0) $display("TEST PASS : activity on/off follows sig");
        else          $display("TEST FAIL");
        $finish;
    end

    initial #2000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
