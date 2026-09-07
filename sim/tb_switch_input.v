`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_switch_input.v   验证消抖：短毛刺不翻转、连续稳定才翻转
//   内部用 clock_enable(MS_DIV=3) 产生 tick_1ms，每 3 个 clk 一个节拍。
//   STABLE_MS=4 ⇒ 某位要连续 4 个 tick 相同才更新 sw_stable。
//------------------------------------------------------------------------------
module tb_switch_input;
    reg clk = 0;
    reg rst_n = 0;
    wire tick_1ms;
    reg [7:0] sw = 8'h00;
    wire [7:0] sw_sync, sw_stable;

    // 被测模块：8 位，稳定 4ms 判有效
    switch_input #(.SW_N(8), .STABLE_MS(4)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .sw(sw), .sw_sync(sw_sync), .sw_stable(sw_stable)
    );

    // 内部 1ms 节拍发生器（等价于 clock_enable #(3)）
    reg [1:0] tcnt = 2'd0;
    always @(posedge clk) begin
        if (!rst_n) tcnt <= 2'd0;
        else        tcnt <= tcnt + 2'd1;
    end
    assign tick_1ms = (tcnt == 2'd0);

    always #10 clk = ~clk;   // 50 MHz

    integer err;
    initial begin
        err = 0;
        $display("=== tb_switch_input start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;

        // ---- 场景1：短毛刺不翻转 ----
        // sw0: 抖 2 个 tick 的 '1'(共 2 tick，< STABLE_MS=4)，应被滤掉
        @(posedge tick_1ms);        // 等一个节拍起点对齐
        sw = 8'h01;
        // 只让 '1' 保持约 2 个 tick，再拉回 0
        repeat (2) begin @(posedge tick_1ms); end
        sw = 8'h00;
        repeat (3) begin @(posedge tick_1ms); end
        if (dut.stable_q[0] === 1'b0)
            $display("PASS 场景1: 2-tick 毛刺被滤除 stable=0");
        else begin
            $display("FAIL 场景1: 毛刺误翻转 stable=%b", dut.stable_q[0]);
            err = err + 1;
        end

        // ---- 场景2：连续 4 tick 才翻转 ----
        sw = 8'h01;
        repeat (6) begin @(posedge tick_1ms); end   // 含同步器 2 拍延迟，取充裕余量
        if (dut.stable_q[0] === 1'b1)
            $display("PASS 场景2: 连续 4 tick 后 stable=1");
        else begin
            $display("FAIL 场景2: stable=%b", dut.stable_q[0]);
            err = err + 1;
        end

        // ---- 场景3：另一路 bit 独立消抖，不受 bit0 影响 ----
        // bit1 也是短毛刺被滤；bit0 保持 1 不变
        sw = 8'h02;                 // bit1=1 单次毛刺（只 1 tick 后拉回）
        @(posedge tick_1ms);
        sw = 8'h01;
        repeat (3) begin @(posedge tick_1ms); end
        if (dut.stable_q[0] === 1'b1 && dut.stable_q[1] === 1'b0)
            $display("PASS 场景3: bit0 保持1、bit1 毛刺被滤");
        else begin
            $display("FAIL 场景3: stable=%b 期望 bit0=1 bit1=0", dut.stable_q);
            err = err + 1;
        end

        // ---- 同步器通路检查 ----
        if (sw_sync === 8'h01)
            $display("PASS 同步器: sw_sync=01 跟随输入");
        else begin
            $display("FAIL 同步器: sw_sync=%b", sw_sync);
            err = err + 1;
        end

        if (err == 0)
            $display("=== tb_switch_input PASS ===");
        else
            $display("=== tb_switch_input FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
