//------------------------------------------------------------------------------
// top_voice_system.v   双引擎(Who+What)语音闭环顶层（综合目标结构）
//   音频特征链: feature_engine → speaker_verify → utter_vote(owner)
//             feature_engine → cmd_matcher  → cmd_vote(cmd)
//   决策: decision_fsm(owner&&cmd) → motion(target 0/90/180 + PID/虚拟电机)
//   遥测: telemetry_voice([AA][owner,cmd,act][tgt][pos][chk])
//   注:
//     - 红线要求不改 .adc，故 ES8388(I2S)与 PLL 未在此含入，aud_* 引脚预留(标 TEST 占位)；
//     - 真实模式 feature 来自 feature_engine；TEST=1 用 dbg_fe_valid/data/owner 注入(仿真场景)；
//     - 板上综合需后续把 ES8388 配置/PLL 与 .adc 扩展接入(见 doc)。
//------------------------------------------------------------------------------
module top_voice_system #(
    parameter TEST   = 0,          // 1=debug 注入(feature/owner)，供仿真
    parameter CTL_DIV = 50000,     // clock_enable(真实 1ms)；仿真改小加速
    parameter VOTE_N = 8
) (
    input  wire              sys_clk,        // R7
    input  wire              sys_rst_n,      // A9
    // ES8388 I2S（预留，真实板接入）
    input  wire              aud_bclk,
    input  wire              aud_lrc,
    input  wire              aud_adcdat,
    output wire              aud_mclk,
    output wire              aud_scl,
    inout  wire              aud_sda,
    output wire              tx,             // UART D12
    output wire [7:0]        led,
    // debug/test：feature 注入(13 维逐维)与 owner
    input  wire              dbg_fe_valid,
    input  wire signed [15:0] dbg_fe_data,
    input  wire              dbg_owner,
    // 观察输出(仿真/上位机)
    output wire              owner_out,
    output wire [1:0]        cmd_id_out,
    output wire [2:0]        action_out,
    output wire [9:0]        pos_deg,
    output wire [9:0]        target_reg
);
    wire rst_n = sys_rst_n;

    // ---- 未用 I2S 占位 ----
    assign aud_mclk = 1'b0; assign aud_scl = 1'b1; assign aud_sda = 1'bz;

    // 1ms 节拍
    wire tick;
    clock_enable #(.MS_DIV(CTL_DIV)) u_ce (
        .clk(sys_clk), .rst_n(rst_n), .tick_1ms(tick));

    // ---- feature_engine（真实音频→特征；TEST 时仍例化但输入不用）----
    wire fe_valid, fe_done, fe_busy;
    wire [3:0] fe_index;
    wire signed [15:0] fe_data;
    feature_engine u_fe (
        .clk(sys_clk), .rst_n(rst_n), .enable(1'b1),
        .frame_start(1'b0), .pcm_valid(1'b0), .pcm_data(24'sd0),
        .busy(fe_busy), .feature_valid(fe_valid), .feature_index(fe_index),
        .feature_data(fe_data), .frame_done(fe_done));

    wire [15:0] fe_data_sel = TEST ? dbg_fe_data : fe_data;
    wire        fe_valid_sel = TEST ? dbg_fe_valid : fe_valid;

    // ---- Who: speaker_verify + utter_vote ----
    wire sv_frame, sv_owner, uv_dec, uv_owner;
    speaker_verify u_sv (
        .clk(sys_clk), .rst_n(rst_n),
        .fe_feature_valid(fe_valid_sel), .fe_index(fe_index), .fe_feature_data(fe_data_sel),
        .frame_valid(sv_frame), .frame_dist(), .frame_match(sv_owner),
        .owner_valid());
    utter_vote #(.VOTE_N(VOTE_N), .MIN_MATCH(VOTE_N/2 + 1)) u_uv (
        .clk(sys_clk), .rst_n(rst_n),
        .frame_valid(sv_frame), .frame_match(sv_owner),
        .decision_valid(uv_dec), .owner_valid(uv_owner), .frames_seen());
    wire owner_sel = TEST ? dbg_owner : uv_owner;

    // ---- What: cmd_matcher + cmd_vote ----
    wire cmd_v, cmd_dec;
    wire [1:0] cmd_id_w;
    cmd_matcher #(
        .TPL0("../../data/commands/cmd_stop.mem"),
        .TPL1("../../data/commands/cmd_left.mem"),
        .TPL2("../../data/commands/cmd_right.mem"),
        .TPL3("../../data/commands/cmd_forward.mem"))
    u_cmd (
        .clk(sys_clk), .rst_n(rst_n), .mfcc_valid(fe_valid_sel), .mfcc_data(fe_data_sel),
        .cmd_valid(cmd_v), .cmd_id(cmd_id_w), .cmd_dist_min());
    cmd_vote #(.VOTE_N(VOTE_N), .NUM(4)) u_cv (
        .clk(sys_clk), .rst_n(rst_n), .cmd_valid(cmd_v), .cmd_id(cmd_id_w),
        .decision_valid(cmd_dec), .cmd_id_out(cmd_id_out), .frames_seen());

    // ---- 联合决策 ----
    wire o_valid;
    wire [2:0] o_act;
    decision_fsm u_dec (
        .clk(sys_clk), .rst_n(rst_n), .in_valid(cmd_dec),
        .in_vad(1'b0), .in_auth(1'b0), .in_dir(2'd0),
        .i_owner_valid(owner_sel), .i_cmd_decision_valid(cmd_dec), .i_cmd_id(cmd_id_out),
        .action_valid(), .action(),
        .o_cmd_valid(o_valid), .o_cmd_action(o_act));

    // ---- 目标映射: 2 forward→90, 3 left→0, 4 right→180, 0/其它→保持 ----
    reg [9:0] target;
    reg move;
    always @(posedge sys_clk) begin
        if (!rst_n) begin target <= 10'd90; move <= 1'b0; end
        else begin
            move <= 1'b0;
            if (o_valid) begin
                case (o_act)
                    3'd2: begin target <= 10'd90;  move <= 1'b1; end
                    3'd3: begin target <= 10'd0;   move <= 1'b1; end
                    3'd4: begin target <= 10'd180; move <= 1'b1; end
                    default: ; // stop/其它保持
                endcase
            end
        end
    end
    assign target_reg = target;

    // ---- 运动闭环: 轨迹→PID→虚拟电机 ----
    wire [9:0] ref_pos;
    trajectory_planner u_traj (
        .clk(sys_clk), .rst_n(rst_n), .tick_ctrl(tick), .en(move),
        .goal(target), .pos0(pos_deg), .ref_pos(ref_pos));
    wire signed [19:0] pid_cmd;
    pid_controller u_pid (
        .clk(sys_clk), .rst_n(rst_n), .tick_ctrl(tick),
        .target(ref_pos), .pos(pos_deg), .cmd(pid_cmd));
    virtual_motor u_mot (
        .clk(sys_clk), .rst_n(rst_n), .tick_ctrl(tick),
        .cmd(pid_cmd), .at_max(), .at_min(), .pos_deg(pos_deg), .vel());

    // ---- 遥测(扩展 owner/cmd) ----
    telemetry_voice #(.TELEM_MS(100), .BAUD_TICKS(434)) u_tlm (
        .clk(sys_clk), .rst_n(rst_n), .tick_1ms(tick),
        .owner(owner_sel), .cmd_id(cmd_id_out), .action(o_act),
        .target(target), .pos(pos_deg), .tx(tx));

    assign owner_out = owner_sel;
    assign action_out = o_act;

    // LED 简单状态
    assign led[0] = owner_sel;
    assign led[7:1] = 7'b0;

endmodule
