`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_uart_telemetry.v
//   把每次 fbyte_ok 派发的字节压入 tb 缓冲区，之后滑动查找
//   完整帧 [AA, state, target, pos, chk] 并核对。
//------------------------------------------------------------------------------
module tb_uart_telemetry;
    reg clk = 0;
    reg rst_n = 0;
    wire tick;
    reg [7:0] state = 0;
    reg [9:0] target = 0;
    reg [9:0] pos = 0;
    wire tx;
    wire [7:0] fbyte;
    wire fbyte_ok;

    reg [1:0] tc = 0;
    always @(posedge clk) begin
        if (!rst_n) tc <= 2'd0;
        else        tc <= tc + 2'd1;
    end
    assign tick = (tc == 2'd0);

    uart_telemetry #(.TELEM_MS(20), .BAUD_TICKS(8)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick),
        .state(state), .target(target), .pos(pos),
        .tx(tx), .fbyte(fbyte), .fbyte_ok(fbyte_ok)
    );

    always #10 clk = ~clk;

    reg [7:0] fbuf [0:63];
    integer wptr = 0;
    always @(posedge clk) begin
        if (!rst_n) wptr <= 0;
        else if (fbyte_ok && wptr < 64) begin
            fbuf[wptr] <= fbyte;
            wptr <= wptr + 1;
        end
    end

    integer i, err, found, cap;
    initial begin
        err = 0; found = 0;
        $display("=== tb_uart_telemetry start ===");
        state = 8'd2; target = 10'd90; pos = 10'd33;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        // 等积累足够字节
        cap = 0;
        while (wptr < 25 && cap < 400000) begin @(posedge clk); cap = cap + 1; end

        for (i = 0; i <= wptr - 5 && !found; i = i + 1) begin
            if (fbuf[i] == 8'hAA &&
                fbuf[i+1] == state && fbuf[i+2] == 8'd90 && fbuf[i+3] == 8'd33 &&
                fbuf[i+4] == (8'hAA ^ state ^ 8'd90 ^ 8'd33))
                found = 1;
        end
        if (found) $display("PASS 找到合法遥测帧 (wptr=%0d)", wptr);
        else begin $display("FAIL 未找到合法帧 wptr=%0d", wptr); err = err + 1; end

        if (err == 0) $display("=== tb_uart_telemetry PASS ===");
        else          $display("=== tb_uart_telemetry FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
