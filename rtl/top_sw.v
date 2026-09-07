//------------------------------------------------------------------------------
// top_sw.v   04 拨码开关采样演示（顶层）
//   SW0 被复位占用，数据用 SW7..SW1 共 7 位：switch_input 采样+消抖后回显到 LED。
//   sw[0]=SW1 … sw[6]=SW7（A10…A14）；led[0] 恒灭，led[i]=开关 SWi 状态(i=1..7)。
//   SW0(A9)=rst_n：拨上=正常运行；拨下=复位。
//   SW 拨上=高(1)=对应 LED 点亮；拨下=低(0)=灭。
// 参数化：MS_DIV / STABLE_MS（消抖稳定毫秒数，仿真改小）。
//------------------------------------------------------------------------------
module top_sw #(
    parameter MS_DIV    = 50000,   // 50MHz -> tick_1ms
    parameter STABLE_MS = 10       // 消抖：连续 10ms 稳定才判变化
) (
    input  wire       clk,
    input  wire       rst_n,       // SW0
    input  wire [6:0] sw,          // SW1..SW7
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    wire [6:0] sw_stable;
    switch_input #(.SW_N(7), .STABLE_MS(STABLE_MS)) u_sw (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .sw(sw), .sw_sync(), .sw_stable(sw_stable)
    );

    assign led = {sw_stable, 1'b0};   // led[7:1]=sw_stable[6:0]，led[0] 恒灭
endmodule
