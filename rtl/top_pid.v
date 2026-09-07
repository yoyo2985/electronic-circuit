//------------------------------------------------------------------------------
// top_pid.v   10 位置环 PID 闭环演示（顶层）
//   真实闭环：target → PID → virtual_motor(反馈 pos) → PID…
//   目标由拨码 SW1(A10) 选择：SW1=0(拨下)→40°，SW1=1(拨上)→120°。
//   数码管实时显示位置 pos(0..180)；LED0=已到位(|err|<=2°)。
//   SW0(A9)=rst_n 拨上=运行。切换 SW1 即见电机平滑转去新目标并停稳。
// 参数化：MS_DIV（及可选 PID/电机参数可另扩）。
//------------------------------------------------------------------------------
module top_pid #(
    parameter MS_DIV = 50000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sw1,        // 目标选择 SW1(A10)
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    wire signed [19:0] cmd;
    wire [9:0] pos;
    wire at_max, at_min;
    wire [9:0] target = sw1 ? 10'd120 : 10'd40;

    pid_controller u_pid (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms),
        .target(target), .pos(pos), .cmd(cmd)
    );

    virtual_motor u_mot (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .cmd(cmd),
        .at_max(at_max), .at_min(at_min), .pos_deg(pos), .vel()
    );

    // 到位指示：|target-pos| <= 2
    wire [9:0] dev = (pos > target) ? (pos - target) : (target - pos);
    wire at_target = (dev <= 10'd2);

    reg [3:0] hun, ten, uni;
    always @(*) begin
        hun = pos / 100;
        ten = (pos / 10) % 10;
        uni = pos % 10;
    end
    wire [3:0] blank = {1'b1, (pos < 100), (pos < 10), 1'b0};

    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({4'd0, hun, ten, uni}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    assign led = {7'b0000000, at_target};
endmodule
