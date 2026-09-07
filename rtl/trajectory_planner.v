//------------------------------------------------------------------------------
// trajectory_planner.v   限速参考轨迹（梯形近似）（11）
//   给 PID 一个“逐步逼近目标”的平滑参考位置，而不是一步跳到 goal，
//   从而限制执行速度、抑制大阶跃冲击（梯形/斜坡限速，加速段近似）。
//   内部位置用 deg<<8 定点：每 tick 最多移动 STEP(≈VEL_DEG_S*0.256)。
//   en 上升沿把轨迹从 pos0 当前测量位置起算，避免起点跳变。
// 输出 ref_pos：整数度(0..POS_MAX)，作为 PID 的目标输入。
// 参数化：VEL_DEG_S / POS_MAX。复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module trajectory_planner #(
    parameter VEL_DEG_S = 45,
    parameter POS_MAX   = 9'd180
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_ctrl,     // 1ms
    input  wire       en,            // 1=按轨迹运行；0=保持
    input  wire [9:0] goal,          // 目标位置 0..POS_MAX
    input  wire [9:0] pos0,          // en 上升沿时的实际位置（起点）
    output reg  [9:0] ref_pos        // 参考位置(整数度)，喂给 PID
);
    localparam STEP = (VEL_DEG_S * 256) / 1000;   // 每 tick 可移动量(deg<<8)
    localparam [31:0] GOALQ = POS_MAX << 8;

    reg signed [17:0] traj;          // deg<<8
    reg en_d1;
    wire en_rise = en && !en_d1;

    always @(posedge clk) begin
        en_d1 <= en;
        if (!rst_n) begin
            traj   <= 18'sd0;
            ref_pos<= 10'd0;
        end else if (en_rise) begin
            // 从当前实际位置开始规划
            traj <= {8'd0, pos0} << 8;
            ref_pos <= pos0;
        end else if (en && tick_ctrl) begin
            if (traj < ({8'd0, goal} << 8) - STEP)      traj <= traj + STEP;
            else if (traj > ({8'd0, goal} << 8) + STEP) traj <= traj - STEP;
            else                                        traj <= {8'd0, goal} << 8;
            // 输出取整并限幅
            if (traj >= GOALQ)          ref_pos <= POS_MAX;
            else if (traj < 0)          ref_pos <= 10'd0;
            else                        ref_pos <= traj[17:8];
        end
    end
endmodule
