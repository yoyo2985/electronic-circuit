//------------------------------------------------------------------------------
// sig_activity.v   活动检测：一根异步信号线是否在翻转 → 点亮/熄灭一个 LED
//   每 WIND_MS(默认200) 看一次：该窗口内只要出现过边沿，on 就拉高并保持；
//   否则拉低。用 2-FF 同步该信号到 sys_clk 域再检测边沿。
// 用途：ES8388 接线自检——把模块回送的 BCK/WS/DO 各接一路，灯亮=那根线在动。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module sig_activity #(
    parameter WIND_MS = 200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire tick_1ms,     // 1ms 节拍
    input  wire sig,          // 被测信号（异步）
    output reg  on            // 1=该信号有活动
);
    // 同步 sig 到本时钟域
    reg s1, s2, s3;
    always @(posedge clk) begin
        if (!rst_n) begin s1 <= 1'b0; s2 <= 1'b0; s3 <= 1'b0; end
        else begin s1 <= sig; s2 <= s1; s3 <= s2; end
    end
    wire tgl = s2 ^ s3;

    reg [7:0]  ms;
    reg        seen;
    always @(posedge clk) begin
        if (!rst_n) begin
            ms   <= 8'd0;
            seen <= 1'b0;
            on   <= 1'b0;
        end else begin
            if (tgl) seen <= 1'b1;
            if (tick_1ms) begin
                if (ms == WIND_MS[7:0] - 1'b1) begin
                    on   <= seen;      // 每窗口刷新一次
                    seen <= 1'b0;
                    ms   <= 8'd0;
                end else begin
                    ms <= ms + 1'b1;
                end
            end
        end
    end
endmodule
