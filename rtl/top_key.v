//------------------------------------------------------------------------------
// top_key.v   05 矩阵键盘演示（顶层）
//   按下 4x4 键盘任意键(消抖后)，把键号 0..15 以十进制显示到数码管：
//     右 1 位=个位、右 2 位=十位(键号<10 时十位消隐)，左边两位不显示。
//   LED3..0 同时回显键号二进制。
//   SW0(A9)=rst_n：拨上=正常运行；拨下=复位。
//   注意：键号为“行优先索引 row*4+col(0..15)”，与丝印编号的对应见板卡布局。
// 参数化：MS_DIV / DEBOUNCE_N（快照消抖次数，仿真改小）。
//------------------------------------------------------------------------------
module top_key #(
    parameter MS_DIV    = 50000,
    parameter DEBOUNCE_N = 3
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] col,       // 读回列（板上 Key_Col）
    output wire [3:0] row,       // 驱动行（板上 Key_Row）
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    wire key_event;
    wire [3:0] key_idx;
    keypad_scan #(.DEBOUNCE_N(DEBOUNCE_N)) u_keypad (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .col_in(col), .row_out(row),
        .key_event(key_event), .key_idx(key_idx)
    );

    // 键号(0..15) -> 两位十进制
    wire [3:0] units = (key_idx < 4'd10) ? key_idx : (key_idx - 4'd10);
    wire [3:0] tens  = (key_idx < 4'd10) ? 4'd0  : 4'd1;
    wire [7:0] bcd   = {tens, units};              // bcd[3:0]=个位 bcd[7:4]=十位

    wire [3:0] blank = {2'b11, (key_idx < 4'd10), 1'b0};   // 千/百位常隐；<10 十位隐

    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({8'd0, bcd}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    assign led = {4'b0000, key_idx};   // LED3..0 = 键号二进制，LED7..4 灭
endmodule
