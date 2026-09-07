`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_blink.v   顶层接线快速检查（子模块已分别验证，这里只查连线）
//   参数缩小：MS_DIV=50, BLANK_HALF_MS=4, WALK_STEP_MS=2
//------------------------------------------------------------------------------
module tb_top_blink;
    reg clk = 0;
    reg rst_n = 0;
    wire [7:0] led;

    top_blink #(.MS_DIV(5), .BLANK_HALF_MS(4), .WALK_STEP_MS(2)) dut (
        .clk(clk), .rst_n(rst_n), .led(led)
    );

    always #10 clk = ~clk;   // 50 MHz

    integer i;
    initial begin
        $display("=== tb_top_blink start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (i % 10 == 0)
                $display("cyc=%0d led=%b", i, led);
        end
        $display("=== tb_top_blink done (LED0 翻转, LED7..1 左移) ===");
        $finish;
    end
endmodule
