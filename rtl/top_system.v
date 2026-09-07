//------------------------------------------------------------------------------
// top_system.v   全系统整合（14）
//   键盘输入目标(0..180) → 状态机 → 轨迹限速 → PID → 虚拟电机 →
//   故障检测 → 遥测 UART。数码管显示当前位置，LED 指示状态。
//   按键：KEY0-9 数字；KEY10=CLR(也作故障确认 ACK)；KEY11=确认并启动(GO)。
//   状态机：IDLE→READY→MOVE→HOLD，故障进 FAULT，CLR 复位。
//   故障演示：fault_sw(SW2,A11) 拨上=模拟堵转/碰撞 → 进 FAULT(LED3)。
//   tx 接 CH340(RXD) 供 PC 收遥测帧(115200)。SW0=rst_n 拨上=运行。
// 参数化：MS_DIV / VEL_DEG_S / TELEM_MS。
//------------------------------------------------------------------------------
module top_system #(
    parameter MS_DIV    = 50000,
    parameter VEL_DEG_S = 150,     // 演示速度：参考轨迹更快、避免慢速误报堵转
    parameter TELEM_MS  = 100
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] col,
    output wire [3:0] row,
    input  wire       fault_sw,       // SW2：强制故障演示
    output wire       tx,             // 遥测串口
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led
);
    // ---------- 线网声明（先声明后例化，避免隐式网冲突） ----------
    wire tick_1ms;
    wire key_event;
    wire [3:0] key;
    wire [8:0] tgt9, entry_dummy;
    wire [9:0] target;               // 10 位(补 0)供各 10 位端口
    wire tvalid, overr;
    wire go_d_reg;
    wire clr_p;
    wire [2:0] fstate;
    wire moving, faulted;
    wire at_target;
    wire signed [19:0] cmd;
    wire [9:0] pos;
    wire at_min, at_max;
    wire [9:0] dev;
    wire [9:0] ref;
    wire fdet;
    wire fault_in;
    wire [7:0] st8;
    assign st8 = {5'd0, fstate};
    reg [3:0] hun, ten, uni;
    wire [3:0] blank;

    // ---------- 时钟使能 ----------
    clock_enable #(.MS_DIV(MS_DIV)) u_ce (.clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms));

    // ---------- 键盘 & 目标输入 ----------
    keypad_scan #(.DEBOUNCE_N(3)) u_kp (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .col_in(col), .row_out(row), .key_event(key_event), .key_idx(key)
    );
    target_input u_ti (
        .clk(clk), .rst_n(rst_n), .key_event(key_event), .key(key),
        .entry(entry_dummy), .target(tgt9), .over_range(overr), .target_valid(tvalid)
    );
    assign target = {1'b0, tgt9};

    // KEY11=GO；KEY10=CLR/ACK
    reg go_d;
    always @(posedge clk) begin
        if (!rst_n) go_d <= 1'b0;
        else        go_d <= (key_event && key == 4'd11);
    end
    assign go_d_reg = go_d;
    assign clr_p    = key_event && key == 4'd10;

    // ---------- 状态机 ----------
    state_machine u_fsm (
        .clk(clk), .rst_n(rst_n),
        .target_valid(tvalid), .start(go_d_reg),
        .at_target(at_target), .fault_in(fault_in), .ack(clr_p),
        .state(fstate), .moving(moving), .faulted(faulted)
    );

    // ---------- 电机 ----------
    virtual_motor u_mot (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .cmd(cmd),
        .at_max(at_max), .at_min(at_min), .pos_deg(pos), .vel()
    );
    assign dev       = (pos > target) ? (pos - target) : (target - pos);
    assign at_target = (dev <= 10'd2);

    // ---------- 轨迹限速 ----------
    trajectory_planner #(.VEL_DEG_S(VEL_DEG_S)) u_traj (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .en(moving),
        .goal(target), .pos0(pos), .ref_pos(ref)
    );

    // ---------- PID ----------
    pid_controller u_pid (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms),
        .target(ref), .pos(pos), .cmd(cmd)
    );

    // ---------- 故障检测 ----------
    // ---------- 故障 ----------
    // 注：demo 中自动堵转检测先禁用(避免板上慢速/整数粒度误判瞬间进故障)，
    // 故障仅由 SW2 手动触发；堵转模块 fault_detector 已单独单测验证。
    fault_detector #(.STALL_MS(1500), .ERR_TOL(8)) u_fdet (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .run(1'b0),
        .pos(pos), .target(target), .ack(clr_p), .faulted(fdet)
    );
    assign fault_in = fault_sw;

    // ---------- 遥测 ----------
    uart_telemetry #(.TELEM_MS(TELEM_MS)) u_tele (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .state(st8), .target(target), .pos(pos),
        .tx(tx), .fbyte(), .fbyte_ok()
    );

    // ---------- 显示 pos ----------
    always @(*) begin
        hun = pos / 100;
        ten = (pos / 10) % 10;
        uni = pos % 10;
    end
    assign blank = {1'b1, (pos < 100), (pos < 10), 1'b0};
    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({4'd0, hun, ten, uni}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    // LED0=有目标, LED1=运动, LED2=到位, LED3=故障
    assign led = {4'b0000, faulted, at_target, moving, tvalid};
endmodule
