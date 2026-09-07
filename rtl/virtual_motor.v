//------------------------------------------------------------------------------
// virtual_motor.v   一阶离散虚拟电机 + 行程限位（09）
//   内部定点整数(<<10)：vel 数值上≈度/秒，pos 为度×1024，pos_deg=pos>>10。
//   每个控制 tick(≈1ms)： pos += vel>>10(每 tick 约 vel_deg_s/1000 度)；
//   速度按一阶时间常数向 cmd 逼近：vel += (cmd-vel)*A/1024, A=1024/TAU_MS。
//   位置限位 [0, MAX_POS_DEG]：到端点速度清零、at_max/at_min=1（模拟关节止挡）。
//   全部中间量用 64 位有符号，避免无符号取反/位宽截断陷阱。
// 输入 cmd：signed，单位 度/秒×1024（如 30 度/秒 => cmd=30720）。
// 参数化：MAX_POS_DEG / MAX_SPD_DEG_S / TAU_MS。复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module virtual_motor #(
    parameter MAX_POS_DEG   = 9'd180,
    parameter MAX_SPD_DEG_S = 16'd60,
    parameter TAU_MS        = 16'd100
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                tick_ctrl,     // 控制 tick（1ms 节拍）
    input  wire signed [19:0]  cmd,           // 期望速度 度/秒×1024，可负
    output reg                at_max,        // 已到上限
    output reg                at_min,        // 已到下限
    output wire [9:0]         pos_deg,       // 当前位置 0..MAX_POS_DEG（度）
    output wire signed [19:0] vel            // 当前速度 度/秒×1024
);
    localparam SHIFT    = 10;
    localparam signed [63:0] POS_MAX = MAX_POS_DEG * (1 << SHIFT);
    localparam signed [63:0] VMAX    = MAX_SPD_DEG_S * (1 << SHIFT);
    localparam signed [63:0] A       = (1 << SHIFT) / TAU_MS;   // 每 tick 逼近比例

    reg signed [63:0] pos;     // 位置，度×1024
    reg signed [63:0] vel_q;   // 速度，度/秒×1024
    reg signed [63:0] e, inc, nv, np;

    always @(posedge clk) begin
        if (!rst_n) begin
            pos    <= 64'sd0;
            vel_q  <= 64'sd0;
            at_max <= 1'b0;
            at_min <= 1'b0;
        end else if (tick_ctrl) begin
            // 一阶速度逼近（全部有符号 64 位）
            e   = $signed(cmd) - vel_q;
            inc = (e * A) >>> SHIFT;
            nv  = vel_q + inc;
            if (nv >  VMAX) nv = VMAX;
            if (nv < -VMAX) nv = -VMAX;
            // 在端点挡阻继续顶
            if (nv > 0 && pos >= POS_MAX) nv = 0;
            if (nv < 0 && pos <= 0)       nv = 0;
            // 位置积分 + 限位
            np = pos + (nv >>> SHIFT);
            if (np > POS_MAX) np = POS_MAX;
            if (np < 0)       np = 0;

            pos    <= np;
            vel_q  <= nv;
            at_max <= (np >= POS_MAX);
            at_min <= (np <= 0);
        end
    end

    assign pos_deg = pos[SHIFT +: 10];   // pos>>10，0..MAX_POS_DEG
    assign vel     = vel_q[19:0];
endmodule
