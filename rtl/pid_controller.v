//------------------------------------------------------------------------------
// pid_controller.v   位置环定点 PID + 三限幅（10）
//   输入：target/pos_deg（整数度 0..180）。输出：cmd = 度/秒×1024（signed），
//   直接接 virtual_motor 的 cmd。控制周期 = tick_ctrl（1ms）。
//   公式（内部先放大 2^PID_SH，最后一次右移，避免中间截断）：
//     err = clamp(target - pos, ±ERR_LIM)
//     p   = KP_EFF * err
//     i   = KI_EFF * acc     (acc += err 每 tick，acc 限幅 ±I_ACC_LIM)
//     d   = KD_EFF * (err - err_prev)
//     cmd = clamp((p + i + d), ±OUT_LIM)
//   默认 KP_EFF=2048 使 cmd=2048*err，即 deg/s = 2*err（无饱和时时间常数 0.5s）。
//   被控对象为速度指令型+积分器，纯 P 已可收敛；KD 抑制超调、KI 消除残差，可自行整定。
// 参数化：KP_EFF/KI_EFF/KD_EFF/PID_SH/ERR_LIM/I_ACC_LIM/OUT_LIM。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module pid_controller #(
    parameter signed [31:0] KP_EFF   = 32'd2048,
    parameter signed [31:0] KI_EFF   = 32'd0,
    parameter signed [31:0] KD_EFF   = 32'd0,
    parameter PID_SH      = 10,
    parameter signed [31:0] ERR_LIM  = 32'd180,
    parameter signed [31:0] I_ACC_LIM = 32'd20000,
    parameter signed [31:0] OUT_LIM   = 32'd61440    // ±60 度/秒×1024
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             tick_ctrl,      // 1ms 控制 tick
    input  wire [9:0]       target,         // 目标 0..180
    input  wire [9:0]       pos,            // 反馈位置 0..180
    output reg  signed [19:0] cmd           // 速度指令 度/秒×1024
);
    localparam signed [63:0] KP = KP_EFF << PID_SH;
    localparam signed [63:0] KI = KI_EFF << PID_SH;
    localparam signed [63:0] KD = KD_EFF << PID_SH;

    reg signed [63:0] acc;       // 积分累加（度·tick）
    reg signed [63:0] err_prev;
    reg signed [63:0] err, derr, term, outv;

    always @(posedge clk) begin
        if (!rst_n) begin
            acc      <= 64'sd0;
            err_prev <= 64'sd0;
            cmd      <= 20'sd0;
        end else if (tick_ctrl) begin
            // 误差限幅（有符号比较，防无符号取负陷阱）
            err = $signed(target) - $signed(pos);
            if (err >  $signed(ERR_LIM)) err = $signed(ERR_LIM);
            if (err < -$signed(ERR_LIM)) err = -$signed(ERR_LIM);

            // 微分（误差变化）
            derr = err - err_prev;

            // 积分累加 + 积分限幅
            acc = acc + err;
            if (acc >  I_ACC_LIM) acc = I_ACC_LIM;
            if (acc < -I_ACC_LIM) acc = -I_ACC_LIM;

            // 三项合成（先放大后右移）
            term = (KP * err) + (KI * acc) + (KD * derr);
            outv = term >>> PID_SH;

            // 输出限幅
            if (outv >  OUT_LIM) outv = OUT_LIM;
            if (outv < -OUT_LIM) outv = -OUT_LIM;

            cmd      <= outv[19:0];
            err_prev <= err;
        end
    end
endmodule
