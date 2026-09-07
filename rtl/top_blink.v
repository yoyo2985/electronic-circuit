//------------------------------------------------------------------------------
// top_blink.v   第一阶段可下板顶层：LED 心跳 + 跑灯
//   clock_enable(50MHz→tick_1ms) → led_ctrl
//   下载到 EG4S20 后：LED0 1Hz 心跳，LED7..1 跑灯循环。
//   参数默认为真实板卡值；仿真时 tb_top_blink 会把 MS_DIV 等改小加速。
//   引脚见 constr/README.md 与 doc/td_flow.md。
//------------------------------------------------------------------------------
module top_blink #(
    parameter MS_DIV        = 50000,   // 50 MHz → 1 kHz
    parameter BLANK_HALF_MS = 500,    // → LED0 1 Hz
    parameter WALK_STEP_MS  = 250     // → 跑灯 4 步/秒
) (
    input  wire        clk,      // 50 MHz, R7
    input  wire        rst_n,    // 复位低有效；接 SW0(A9)，拨上=运行 / 拨下=复位
    output wire [7:0]  led       // LED0..LED7
);
    wire tick_1ms;

    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    led_ctrl #(.BLANK_HALF_MS(BLANK_HALF_MS), .WALK_STEP_MS(WALK_STEP_MS)) u_led (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms), .led(led)
    );
endmodule
