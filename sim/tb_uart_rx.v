`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_uart_rx.v   UART 接收验证
//   BAUD_TICKS=8。行为发送端按位时序驱动 rx（空闲高、起始0、8 数据位 LSB 先、停止1）。
//   验证 0xA5、0x55 正确解码；另注入 <半位 的短低毛刺，应被拒收(无 rx_done)。
//------------------------------------------------------------------------------
module tb_uart_rx;
    reg clk = 0;
    reg rst_n = 0;
    reg rx = 1;
    wire rx_done;
    wire [7:0] rx_data;
    wire rx_busy;

    uart_rx #(.BAUD_TICKS(8)) dut (
        .clk(clk), .rst_n(rst_n), .rx(rx),
        .rx_done(rx_done), .rx_data(rx_data), .rx_busy(rx_busy)
    );

    always #10 clk = ~clk;

    task automatic send_frame(input [7:0] byte);
        integer b, i;
        begin
            rx = 1'b0;                       // 起始位
            for (i = 0; i < 8; i = i + 1) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                rx = byte[b];                // LSB 先行
                for (i = 0; i < 8; i = i + 1) @(posedge clk);
            end
            rx = 1'b1;                       // 停止位
            for (i = 0; i < 8; i = i + 1) @(posedge clk);
        end
    endtask

    integer err, i;
    reg [7:0] exp;
    initial begin
        err = 0;
        $display("=== tb_uart_rx start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        rx = 1'b1;
        repeat (10) @(posedge clk);

        // ---- 毛刺拒收：2 拍低(< B/2=4) ----
        @(posedge clk); rx = 1'b0;
        repeat (2) @(posedge clk);
        rx = 1'b1;
        repeat (20) @(posedge clk);
        if (rx_done == 1'b0 && dut.r2 == 1'b1)
            $display("PASS 毛刺拒收: 无 rx_done");
        else begin $display("FAIL 毛刺被误收: rx_done=%b", rx_done); err = err + 1; end

        // ---- 接收 0xA5 ----
        send_frame(8'hA5);
        i = 0; while (!rx_done && i < 200) begin @(posedge clk); i = i + 1; end
        if (rx_done && rx_data == 8'hA5)
            $display("PASS 收到 0xA5 = %b", rx_data);
        else begin $display("FAIL 0xA5 收到 %b", rx_data); err = err + 1; end

        // ---- 接收 0x55 ----
        send_frame(8'h55);
        i = 0; while (!rx_done && i < 200) begin @(posedge clk); i = i + 1; end
        if (rx_done && rx_data == 8'h55)
            $display("PASS 收到 0x55 = %b", rx_data);
        else begin $display("FAIL 0x55 收到 %b", rx_data); err = err + 1; end

        // ---- 连接发送：0x01 紧跟 0x80 ----
        send_frame(8'h01);
        i = 0; while (!rx_done && i < 200) begin @(posedge clk); i = i + 1; end
        if (rx_data == 8'h01) $display("PASS 收到 0x01");
        else begin $display("FAIL 0x01 收到 %b", rx_data); err = err + 1; end
        send_frame(8'h80);
        i = 0; while (!rx_done && i < 200) begin @(posedge clk); i = i + 1; end
        if (rx_data == 8'h80) $display("PASS 收到 0x80");
        else begin $display("FAIL 0x80 收到 %b", rx_data); err = err + 1; end

        if (err == 0)
            $display("=== tb_uart_rx PASS ===");
        else
            $display("=== tb_uart_rx FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
