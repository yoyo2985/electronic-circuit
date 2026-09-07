`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_uart_tx.v   UART 发送验证
//   BAUD_TICKS=8（仿真），时钟 20ns/周期。
//   对 0xA5、0x3C 各发一帧，在数据位中心采样重建字节，须与发送一致；
//   校验空闲电平为高、帧结束后 busy 回落、可连续再发。
//------------------------------------------------------------------------------
module tb_uart_tx;
    reg clk = 0;
    reg rst_n = 0;
    reg send = 0;
    reg [7:0] tx_data = 8'h00;
    wire tx;
    wire busy;

    uart_tx #(.BAUD_TICKS(8)) dut (
        .clk(clk), .rst_n(rst_n), .send(send), .tx_data(tx_data),
        .tx(tx), .busy(busy)
    );

    always #10 clk = ~clk;      // 50 MHz

    reg [15:0] cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // 采样一帧的 8 个数据位；M 为 send 拉高的那一拍
    task automatic get_frame(input integer M, output [7:0] got);
        integer k, target;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                target = M + 1 + (k + 1) * 8 + 4;      // T_k + B/2 处采样
                while (cyc < target) @(posedge clk);
                got[k] = tx;
            end
        end
    endtask

    integer err;
    integer M;
    reg [7:0] got;
    initial begin
        err = 0;
        $display("=== tb_uart_tx start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- 空闲：tx=1, busy=0 ----
        if (tx === 1'b1 && busy === 1'b0)
            $display("PASS 空闲电平: tx=1 busy=0");
        else begin $display("FAIL 空闲: tx=%b busy=%b", tx, busy); err = err + 1; end

        // ---- 发送 0xA5 (1010_0101, LSB 先行) ----
        tx_data = 8'hA5;
        @(posedge clk); M = cyc; send = 1'b1;
        @(posedge clk); send = 1'b0;
        repeat (2) @(posedge clk);          // 等 busy 被 RTL 采样置位
        if (busy === 1'b1) $display("PASS busy 拉高");
        else begin $display("FAIL busy 未拉高"); err = err + 1; end
        get_frame(M, got);
        if (got == 8'hA5)
            $display("PASS 收到 0xA5 = %b", got);
        else begin $display("FAIL 0xA5 收到 %b", got); err = err + 1; end

        // ---- 等待帧结束，busy 回落、tx 回高 ----
        while (cyc < M + 11 * 8 + 6) @(posedge clk);
        if (busy === 1'b0 && tx === 1'b1)
            $display("PASS 帧结束: busy=0 tx=1");
        else begin $display("FAIL 帧结束: busy=%b tx=%b", busy, tx); err = err + 1; end

        // ---- 再发 0x3C ----
        tx_data = 8'h3C;
        @(posedge clk); M = cyc; send = 1'b1;
        @(posedge clk); send = 1'b0;
        get_frame(M, got);
        if (got == 8'h3C)
            $display("PASS 收到 0x3C = %b", got);
        else begin $display("FAIL 0x3C 收到 %b", got); err = err + 1; end

        if (err == 0)
            $display("=== tb_uart_tx PASS ===");
        else
            $display("=== tb_uart_tx FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
