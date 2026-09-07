`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_led_ctrl.v
// 验证：LED0 心跳翻转；LED7..1 跑灯左移。
// 仿真参数缩小：BLANK_HALF_MS=4, WALK_STEP_MS=2；tick 每 5 个 clk 一拍。
//------------------------------------------------------------------------------
module tb_led_ctrl;
    reg clk = 0;
    reg rst_n = 0;
    reg tick = 0;
    wire [7:0] led;

    led_ctrl #(.BLANK_HALF_MS(4), .WALK_STEP_MS(2)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick), .led(led)
    );

    always #10 clk = ~clk;

    // 产生 tick：每 5 个 clk 一拍（模拟 1 ms）
    reg [2:0] td = 0;
    always @(posedge clk) begin
        if (td == 3'd4) begin td <= 3'd0; tick <= 1'b1; end
        else            begin td <= td + 3'd1; tick <= 1'b0; end
    end

    integer i;
    initial begin
        $display("=== tb_led_ctrl start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (i % 10 == 0)
                $display("cyc=%0d led=%b (LED0=心跳, LED7..1=跑灯)", i, led);
        end
        $display("=== tb_led_ctrl done (看波形：LED0 周期翻转, LED7..1 单 bit 左移) ===");
        $finish;
    end
endmodule
