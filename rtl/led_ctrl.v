//------------------------------------------------------------------------------
// led_ctrl.v   第一阶段：LED 闪烁 / 跑灯（验证时钟与基本输出）
//   LED0      ：1 Hz 心跳（系统在运行）
//   LED7..LED1：跑灯，每 WALK_STEP_MS ms 左移一位
// 板上 LED 为高电平点亮（引脚见 constr/README.md）。LED0~7 与 R-2R DAC 复用，
// 第一阶段不使用 DAC，故可作 LED。
// 输入 tick_1ms 来自 clock_enable，本模块不产生新时钟。
//------------------------------------------------------------------------------
module led_ctrl #(
    parameter BLANK_HALF_MS = 500,   // 半周期 500 ms ⇒ 1 Hz
    parameter WALK_STEP_MS  = 250    // 每 250 ms 跑灯左移一位
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,      // 1 ms 节拍
    output reg  [7:0] led            // {LED7..LED0}，高=点亮
);
    // ---- LED0 心跳 ----
    reg [15:0] blink_cnt;
    reg        blink;
    // ---- LED7..1 跑灯（7 位中始终 1 位为 1）----
    reg [15:0] walk_cnt;
    reg [6:0]  walk;

    always @(posedge clk) begin
        if (!rst_n) begin
            blink_cnt <= 16'd0;
            blink     <= 1'b0;
            walk_cnt  <= 16'd0;
            walk      <= 7'b000_0001;   // 亮 LED1
        end else if (tick_1ms) begin
            // 心跳：计满半周期翻转
            if (blink_cnt == BLANK_HALF_MS - 1) begin
                blink_cnt <= 16'd0;
                blink     <= ~blink;
            end else begin
                blink_cnt <= blink_cnt + 16'd1;
            end
            // 跑灯：计满步长左移一位（7 位循环）
            if (walk_cnt == WALK_STEP_MS - 1) begin
                walk_cnt <= 16'd0;
                walk     <= {walk[5:0], walk[6]};   // 7 位左循环
            end else begin
                walk_cnt <= walk_cnt + 16'd1;
            end
        end
    end

    // 组合输出：LED0=心跳，LED7..1=跑灯
    always @(*) begin
        led[0]   = blink;
        led[7:1] = walk;
    end
endmodule
