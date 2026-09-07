`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_uart_loop.v   loopback 胶水验证：在 TB 内把 tx 与 rx 短接，
//   验证发送的 '0','1','2' 能经 uart_rx 收回来并显示(内部逻辑)。
//   仿真参数：MS_DIV=8、BAUD_TICKS=8、GAP_MS=3。
//------------------------------------------------------------------------------
module tb_top_uart_loop;
    reg clk = 0;
    reg rst_n = 0;
    wire loop;                    // TB 层短接
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;

    top_uart_loop #(.MS_DIV(8), .BAUD_TICKS(8), .GAP_MS(3)) dut (
        .clk(clk), .rst_n(rst_n), .rx(loop), .tx(loop),
        .seg(seg), .dig_cs(dig_cs), .led(led)
    );

    always #10 clk = ~clk;

    reg done_p = 0;
    always @(posedge clk) done_p <= dut.u_rx.rx_done;
    wire rx_rise = dut.u_rx.rx_done && !done_p;

    integer i, err;
    reg [7:0] arr [0:2];
    initial begin
        err = 0;
        $display("=== tb_top_uart_loop start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // 跳过启动期前两帧（TB 在 t0 的 x 态会吃掉一帧，真实板上无此现象）
        for (i = 0; i < 2; i = i + 1) begin
            while (!rx_rise) @(posedge clk);
        end

        // 连续收 3 帧：应为三个连续递增的数字字符
        for (i = 0; i < 3; i = i + 1) begin
            while (!rx_rise) @(posedge clk);
            repeat (1) @(posedge clk);
            arr[i] = dut.u_rx.rx_data;
        end

        if (arr[0] + 1 == arr[1] && arr[1] + 1 == arr[2] &&
            arr[0] >= 8'h30 && arr[2] <= 8'h38)
            $display("PASS 连续接收: %c,%c,%c 递增", arr[0], arr[1], arr[2]);
        else begin
            $display("FAIL 连续接收: 0x%h,0x%h,0x%h 应递增", arr[0], arr[1], arr[2]);
            err = err + 1;
        end

        // 显示应与最后一帧一致
        if (dut.show_valid && dut.show == arr[2] - 8'h30)
            $display("PASS 显示: show=%0d", dut.show);
        else begin
            $display("FAIL 显示: show_valid=%b show=%0d (末帧 %c)", dut.show_valid, dut.show, arr[2]);
            err = err + 1;
        end

        if (err == 0)
            $display("=== tb_top_uart_loop PASS ===");
        else
            $display("=== tb_top_uart_loop FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
