//------------------------------------------------------------------------------
// top_motor.v   09 虚拟电机演示（顶层）
//   自动演示：电机先正转冲到 180(顶住)，再反转回到 0，循环往复。
//   数码管实时显示当前位置(0..180，右对齐去前导0)。
//   LED0=方向(1=正转)，LED1=到端点(at_max|at_min)。
//   SW0(A9)=rst_n 拨上=运行。参数化 MS_DIV/SPD_DEG_S(默认20度/秒)。
//------------------------------------------------------------------------------
module top_motor #(
    parameter MS_DIV    = 50000,
    parameter SPD_DEG_S = 20
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    wire [9:0] pos_deg;
    wire at_max, at_min;
    reg dir = 1'b1;
    always @(posedge clk) begin
        if (!rst_n)           dir <= 1'b1;
        else if (at_max && dir) dir <= 1'b0;   // 顶到上限 → 反转
        else if (at_min && !dir) dir <= 1'b1;  // 回到下限 → 正转
    end
    localparam SPD_Q = SPD_DEG_S * 1024;
    wire signed [19:0] cmd = dir ? SPD_Q : -SPD_Q;

    virtual_motor u_mot (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .cmd(cmd),
        .at_max(at_max), .at_min(at_min), .pos_deg(pos_deg), .vel()
    );

    reg [3:0] hun, ten, uni;
    always @(*) begin
        hun = pos_deg / 100;
        ten = (pos_deg / 10) % 10;
        uni = pos_deg % 10;
    end
    wire [3:0] blank = {1'b1, (pos_deg < 100), (pos_deg < 10), 1'b0};

    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({4'd0, hun, ten, uni}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    assign led = {6'b000000, (at_max | at_min), dir};
endmodule
