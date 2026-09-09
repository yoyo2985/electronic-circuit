// beep_gen : 无源蜂鸣器方波脉冲音发生器
//
// 用法：trigger 单拍脉冲启动一次蜂鸣，tick_1ms 为 1ms 时钟使能（仿真可加速）。
// 蜂鸣输出为 FREQ_HZ 方波，持续 DUR_MS 个 tick 后自动停止、回到低电平。
// 若蜂鸣尚未结束又收到 trigger，则重新开始。
//
// 全部时间参数均可参数化：
//   CLK_FREQ_HZ : 系统时钟频率（用于计算半周期）
//   FREQ_HZ     : 蜂鸣音频率（决定方波半周期拍数）
//   DUR_MS      : 蜂鸣时长（单位：tick_1ms 个数）
module beep_gen #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter FREQ_HZ     = 2000,
    parameter DUR_MS      = 100
)(
    input  wire clk,
    input  wire rst_n,      // 同步低有效复位
    input  wire tick_1ms,   // 1ms 时钟使能
    input  wire trigger,    // 单拍脉冲：启动一次蜂鸣
    output reg  buzzer      // 驱动无源蜂鸣器（方波）
);

    // 方波半周期拍数：每 HALF 拍翻转一次，得 FREQ_HZ 频率
    localparam HALF = CLK_FREQ_HZ / (FREQ_HZ * 2);
    // 时长计数宽度
    localparam DC_W = $clog2(DUR_MS + 1);

    reg [$clog2(HALF):0] hc;   // 半周期计数
    reg [DC_W-1:0]       dc;   // 时长计数（倒数）
    reg                  active;

    always @(posedge clk) begin
        if (!rst_n) begin
            active <= 1'b0;
            buzzer <= 1'b0;
            hc     <= 'd0;
            dc     <= 'd0;
        end else if (trigger) begin
            active <= 1'b1;
            hc     <= 'd0;
            dc     <= DUR_MS - 1;
            buzzer <= 1'b1;
        end else if (active) begin
            if (hc == HALF - 1) begin
                hc     <= 'd0;
                buzzer <= ~buzzer;
            end else begin
                hc     <= hc + 1;
            end
            if (tick_1ms) begin
                if (dc == 0) begin
                    active <= 1'b0;
                    buzzer <= 1'b0;
                end else begin
                    dc <= dc - 1;
                end
            end
        end else begin
            buzzer <= 1'b0;
        end
    end

endmodule
