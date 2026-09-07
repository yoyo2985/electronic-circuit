//------------------------------------------------------------------------------
// top_seg.v   03 数码管：0~9999 递增计数显示（顶层）
//   验证目标：clock_enable 产生 tick_1ms 做扫描节拍；每 1s 触发一次 BCD 自增；
//             seven_seg 把 4 位 BCD 动态扫描到 4 位共阴数码管上。
//   引脚：seg[7:0]=Digitron_Out[7:0]（A..G,DOT），dig_cs[3:0]=DigitronCS_Out[3:0]
//   计时参数 parameter 化：仿真时改小 MS_DIV / INC_MS。
//   复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module top_seg #(
    parameter MS_DIV = 50000,   // 1ms 分频数（50MHz/50000=1ms）
    parameter INC_MS = 1000     // 计数自增周期：每 1000ms 加 1
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  seg,      // 字码段，接 Digitron_Out[7:0]
    output wire [3:0]  dig_cs    // 位选，接 DigitronCS_Out[3:0]（低有效）
);
    // 1) 1ms 节拍：同时用作扫描节拍
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    // 2) 每 INC_MS 毫秒产生一个 tick_inc
    reg        tick_inc;
    reg [9:0]  inc_cnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            inc_cnt  <= 10'd0;
            tick_inc <= 1'b0;
        end else begin
            tick_inc <= 1'b0;                 // 默认清零，只在一个周期为 1
            if (tick_1ms) begin
                if (inc_cnt == INC_MS - 1) begin
                    inc_cnt  <= 10'd0;
                    tick_inc <= 1'b1;
                end else
                    inc_cnt <= inc_cnt + 10'd1;
            end
        end
    end

    // 3) 4 位 BCD 计数器 0~9999（个位 bcd0 … 千位 bcd3）
    reg [3:0] bcd0, bcd1, bcd2, bcd3;
    always @(posedge clk) begin
        if (!rst_n) begin
            bcd0 <= 4'd0; bcd1 <= 4'd0; bcd2 <= 4'd0; bcd3 <= 4'd0;
        end else if (tick_inc) begin
            if (bcd0 == 4'd9) begin
                bcd0 <= 4'd0;
                if (bcd1 == 4'd9) begin
                    bcd1 <= 4'd0;
                    if (bcd2 == 4'd9) begin
                        bcd2 <= 4'd0;
                        bcd3 <= (bcd3 == 4'd9) ? 4'd0 : bcd3 + 4'd1;   // 9999 -> 0000
                    end else
                        bcd2 <= bcd2 + 4'd1;
                end else
                    bcd1 <= bcd1 + 4'd1;
            end else
                bcd0 <= bcd0 + 4'd1;
        end
    end

    wire [15:0] bcd_data = {bcd3, bcd2, bcd1, bcd0};

    // 4) 动态扫描显示
    seven_seg u_seg (
        .clk(clk),
        .rst_n(rst_n),
        .tick_scan(tick_1ms),   // 1ms/位 => 250Hz/位，视觉无闪烁
        .bcd_data(bcd_data),
        .points(4'b0000),
        .blank(4'b0000),        // 全显示，含前导 0（如 0007）
        .seg(seg),
        .dig_cs(dig_cs)
    );
endmodule
