//------------------------------------------------------------------------------
// clock_enable.v
// 50 MHz 主时钟 → 周期为 1 个时钟宽的 enable 脉冲 (tick_1ms)
// 设计原则：用 "clock enable" 而不是分频出来的新时钟，
//           整个工程只保留一个 50 MHz 时钟域，避免多时钟域问题。
// 复位：同步、低有效 rst_n（本工程统一约定，见 doc/design_rules.md）
// 仿真：把 MS_DIV 改小即可加速，例如 MS_DIV=10
//------------------------------------------------------------------------------
module clock_enable #(
    parameter MS_DIV = 50000      // 50 MHz / 50000 = 1 kHz ⇒ 每 1 ms 一个脉冲
) (
    input  wire clk,             // 50 MHz 系统时钟
    input  wire rst_n,           // 同步复位，低有效
    output reg  tick_1ms        // 每 MS_DIV 个时钟拉高 1 拍
);
    // 根据分频比自动算出计数器位宽（Verilog-2005 $clog2）。要求 MS_DIV ≥ 2。
    localparam CNT_W = $clog2(MS_DIV);
    reg [CNT_W-1:0] cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt      <= {CNT_W{1'b0}};
            tick_1ms <= 1'b0;
        end else begin
            if (cnt == MS_DIV - 1) begin
                cnt      <= {CNT_W{1'b0}};
                tick_1ms <= 1'b1;     // 计满，发一个 1 拍脉冲
            end else begin
                cnt      <= cnt + 1'b1;
                tick_1ms <= 1'b0;
            end
        end
    end
endmodule
