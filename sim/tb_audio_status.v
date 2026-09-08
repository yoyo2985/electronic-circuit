//------------------------------------------------------------------------------
// tb_audio_status.v   验证 0.5s 状态行（单次发射版）：
//   tick 每 400clk 一次，PERIOD_MS=4 → 第 4 个 tick 发一行。
//   期间注入 3 个 frame_ok、e_l=0x1234、e_r=0xABCD，
//   收到的第一行应为 "P0003 L1234 RABCD\n"。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_audio_status;

    localparam B = 8;
    localparam TICK_GAP = 400;         // clk
    reg clk = 1'b0, rst_n = 1'b0;
    reg tick_1ms = 1'b0, frame_ok = 1'b0;
    reg [15:0] e_l = 0, e_r = 0;
    wire tx;

    audio_status #(.BAUD_TICKS(B), .VAL_W(16), .PERIOD_MS(4)) DUT (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms), .frame_ok(frame_ok),
        .e_l(e_l), .e_r(e_r), .tx(tx)
    );

    always #10 clk = ~clk;

    // tick：每 TICK_GAP clk 一次
    reg [9:0] tc;
    always @(posedge clk) begin
        if (!rst_n) begin tc <= 0; tick_1ms <= 1'b0; end
        else begin
            tick_1ms <= 1'b0;
            if (tc == TICK_GAP - 1) begin tick_1ms <= 1'b1; tc <= 0; end
            else tc <= tc + 1'b1;
        end
    end

    // 接收端
    wire rx_done;
    wire [7:0] rx_data;
    uart_rx #(.BAUD_TICKS(B)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(tx),
        .rx_done(rx_done), .rx_data(rx_data), .rx_busy()
    );

    reg [7:0] rb[0:31];
    integer n = 0;
    integer bad = 0;
    reg first_done = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin n <= 0; bad <= 0; first_done <= 1'b0; end
        else if (rx_done && !first_done) begin
            rb[n] <= rx_data;
            n <= n + 1;
            if (n == 17) first_done <= 1'b1;   // 第一行收完即停
        end
    end

    task expect;
        input integer i;
        input [7:0] c;
        begin
            if (i >= n || rb[i] !== c) begin
                $display("[ERR] byte %0d = %02h want %02h", i, (i<n?rb[i]:8'h00), c);
                bad = bad + 1;
            end
        end
    endtask

    integer k;
    initial begin
        rst_n = 1'b0;
        repeat(6) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        e_l = 16'h1234;
        e_r = 16'hABCD;
        for (k = 0; k < 3; k = k + 1) begin
            frame_ok = 1'b1;
            @(posedge clk);
            frame_ok = 1'b0;
            repeat(40) @(posedge clk);
        end

        // 等第一行收完（事件驱动，不依赖 timescale 换算）
        while (!first_done) @(posedge clk);
        #100;

        expect(0, "P");
        expect(1, "0"); expect(2, "0"); expect(3, "0"); expect(4, "3");
        expect(5,  " ");
        expect(6, "L");
        expect(7, "1"); expect(8, "2"); expect(9, "3"); expect(10, "4");
        expect(11, " ");
        expect(12, "R");
        expect(13, "A"); expect(14, "B"); expect(15, "C"); expect(16, "D");
        expect(17, "\n");

        if (bad == 0)
            $display("TEST PASS : first line 'P0003 L1234 RABCD' n=%0d", n);
        else
            $display("TEST FAIL : bad=%0d n=%0d", bad, n);
        $finish;
    end

    initial #1500000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
