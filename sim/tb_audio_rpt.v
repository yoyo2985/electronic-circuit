//------------------------------------------------------------------------------
// tb_audio_rpt.v   验证音频 ASCII 上报：
//   喂 v_l=0x1234 v_r=0xabcd，触发一次，用 uart_rx(BAUD=8) 收串，
//   应收到 "L1234 Rabcd\n"（12 字节）→ TEST PASS。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_audio_rpt;

    localparam B = 8;                       // 仿真波特率分频
    reg clk = 1'b0, rst_n = 1'b0;
    reg trigger = 1'b0;
    reg [15:0] v_l = 0, v_r = 0;
    wire tx;

    audio_rpt #(.BAUD_TICKS(B)) DUT (
        .clk(clk), .rst_n(rst_n), .trigger(trigger),
        .v_l(v_l), .v_r(v_r), .tx(tx)
    );

    always #10 clk = ~clk;                  // 50MHz

    // UART 接收端（用工程里已仿真的 uart_rx）
    wire rx_done;
    wire [7:0] rx_data;
    uart_rx #(.BAUD_TICKS(B)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(tx),
        .rx_done(rx_done), .rx_data(rx_data), .rx_busy()
    );

    reg [7:0] rb[0:31];
    integer n = 0;
    integer bad = 0;
    reg got_line = 1'b0;

    always @(posedge clk) begin
        if (!rst_n) begin n <= 0; got_line <= 1'b0; bad <= 0; end
        else if (rx_done) begin
            rb[n] <= rx_data;
            if (rx_data == "\n") got_line <= 1'b1;
            n <= n + 1;
            if (n >= 31) bad <= bad + 1;   // 防溢出
        end
    end

    task expect;
        input integer i;
        input [7:0] c;
        begin
            if (i >= n || rb[i] !== c) begin
                $display("[ERR] byte %0d = %02h want %02h ('%c')", i, (i<n?rb[i]:8'h00), c, c);
                bad = bad + 1;
            end
        end
    endtask

    integer j;
    initial begin
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);

        v_l = 16'h1234;
        v_r = 16'habcd;
        trigger = 1'b1;
        @(posedge clk);
        trigger = 1'b0;

        // 等一整行（12 字节 * (10 bit * 160ns) ≈ 19us + 裕量）
        #100000;

        // 预期 "L1234 Rabcd\n"
        expect(0,  "L"); expect(1, "1"); expect(2, "2"); expect(3, "3"); expect(4, "4");
        expect(5,  " "); expect(6, "R");
        expect(7,  "A"); expect(8, "B"); expect(9, "C"); expect(10, "D");
        expect(11, "\n");

        if (bad == 0)
            $display("TEST PASS : got %0d-byte line 'L1234 RABCD'", n);
        else
            $display("TEST FAIL : bad=%0d n=%0d", bad, n);
        $finish;
    end

    initial #400000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
