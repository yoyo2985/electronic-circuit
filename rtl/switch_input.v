//------------------------------------------------------------------------------
// switch_input.v   拨码开关采样：两级同步 + 逐位消抖
//   1) 两级同步器(sync1/sync2)把异步开关电平接入 clk 域，抑制亚稳态。
//   2) 消抖：每一位电平需连续稳定 STABLE_MS 个 tick_1ms 才更新 sw_stable，
//      弹跳产生的短暂毛刺(不足 STABLE_MS)被滤除。
//   板上电平：拨下=低(0)、拨上=高(1)。原始输入不打折，直接取同步后电平。
// 参数化：SW_N 位宽、STABLE_MS 稳定毫秒数(仿真改小)。
// 复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module switch_input #(
    parameter SW_N     = 8,
    parameter STABLE_MS = 10
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             tick_1ms,   // 1ms 节拍，来自 clock_enable
    input  wire [SW_N-1:0]  sw,         // 原始拨码输入
    output wire [SW_N-1:0]  sw_sync,    // 同步后电平（未消抖）
    output wire [SW_N-1:0]  sw_stable   // 消抖后稳定值
);
    // ---- 两级同步器 ----
    reg [SW_N-1:0] sync1, sync2;
    always @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= {SW_N{1'b0}};
            sync2 <= {SW_N{1'b0}};
        end else begin
            sync1 <= sw;
            sync2 <= sync1;
        end
    end
    assign sw_sync = sync2;

    // ---- 逐位消抖 ----
    localparam CNT_W = $clog2(STABLE_MS);              // 计数器位宽
    reg [SW_N-1:0] stable_q;
    reg [CNT_W-1:0] cnt [SW_N-1:0];                    // 每位一个计数
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            stable_q <= {SW_N{1'b0}};
            for (i = 0; i < SW_N; i = i + 1)
                cnt[i] <= {CNT_W{1'b0}};
        end else if (tick_1ms) begin
            for (i = 0; i < SW_N; i = i + 1) begin
                if (sync2[i] != stable_q[i]) begin     // 出现了不同电平
                    if (cnt[i] == STABLE_MS - 1)       // 连续稳定满 STABLE_MS 次才翻转
                        stable_q[i] <= sync2[i];
                    cnt[i] <= cnt[i] + 1'b1;
                end else begin
                    cnt[i] <= {CNT_W{1'b0}};           // 回到原电平，计数清零
                end
            end
        end
    end
    assign sw_stable = stable_q;
endmodule
