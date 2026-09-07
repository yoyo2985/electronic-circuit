`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_seven_seg.v
// 验证：4 位轮流选中；显示 "090"（最左位消隐）。
//   bcd_data=16'h0090 ⇒ 千位0/百位0/十位9/个位0；blank=4'b1000 消隐千位 ⇒ " 090"
//------------------------------------------------------------------------------
module tb_seven_seg;
    reg clk = 0;
    reg rst_n = 0;
    reg tick = 0;
    reg [15:0] bcd_data;
    reg [3:0]  points;
    reg [3:0]  blank;
    wire [7:0] seg;
    wire [3:0] dig_cs;

    seven_seg dut (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick),
        .bcd_data(bcd_data), .points(points), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    always #10 clk = ~clk;

    // 产生 tick：每 4 个 clk 一拍（扫描节拍）
    reg [1:0] td = 0;
    always @(posedge clk) begin
        if (td == 2'd3) begin td <= 2'd0; tick <= 1'b1; end
        else            begin td <= td + 2'd1; tick <= 1'b0; end
    end

    integer i;
    initial begin
        $display("=== tb_seven_seg start ===");
        bcd_data = 16'h0090;   // 显示 090
        points   = 4'b0000;
        blank    = 4'b1000;   // 消隐最左位
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge clk);
            if (tick)
                $display("tick: dig_cs=%b seg=%b  (期望 idx0:1110/00111111 idx1:1101/01101111 idx2:1011/00111111 idx3:0111/00000000)",
                         dig_cs, seg);
        end
        $display("=== tb_seven_seg done (看波形：4 位轮选, 段码符合字形表) ===");
        $finish;
    end
endmodule
