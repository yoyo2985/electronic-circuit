`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_uart_tx.v   top_uart_tx 胶水验证（串行帧本身由 tb_uart_tx 验证）
//   验证自动发送控制器：u_tx.busy 每发一帧拉高一次，digit 依次 =1,2,3,...
//   (digit 在发送时已自增：第1帧字符'0' 后 digit=1，第2帧字符'1' ...)
//   仿真参数：MS_DIV=8、BAUD_TICKS=8、GAP_MS=3。
//------------------------------------------------------------------------------
module tb_top_uart_tx;
    reg clk = 0;
    reg rst_n = 0;
    wire tx;
    wire [7:0] led;

    top_uart_tx #(.MS_DIV(8), .BAUD_TICKS(8), .GAP_MS(3)) dut (
        .clk(clk), .rst_n(rst_n), .tx(tx), .led(led)
    );

    always #10 clk = ~clk;

    reg busy_p = 0;               // 上一拍 busy
    always @(posedge clk) busy_p <= dut.u_tx.busy;
    wire busy_rise = dut.u_tx.busy && !busy_p;

    integer i, err;
    initial begin
        err = 0;
        $display("=== tb_top_uart_tx start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        for (i = 0; i < 3; i = i + 1) begin
            while (!busy_rise) @(posedge clk);   // 等第 i+1 帧开始
            repeat (2) @(posedge clk);
            if (dut.digit == i + 1)
                $display("PASS 第%0d帧: digit=%0d", i+1, dut.digit);
            else begin
                $display("FAIL 第%0d帧 digit=%0d 期望 %0d", i+1, dut.digit, i+1);
                err = err + 1;
            end
            // 等该帧结束（busy 回落）
            while (dut.u_tx.busy) @(posedge clk);
        end

        if (err == 0)
            $display("=== tb_top_uart_tx PASS ===");
        else
            $display("=== tb_top_uart_tx FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
