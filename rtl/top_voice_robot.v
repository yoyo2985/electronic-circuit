//------------------------------------------------------------------------------
// top_voice_robot.v  唯一最终顶层 —— Phase 1：V1 运动全复用 + 语音命令缝
//   数据流(与 top_system 完全同构，不改任何已验证模块)：
//     [键盘] keypad_scan → target_input → {tgt9, tvalid}   (V1 原样)
//     [语音缝] v_act_valid/v_act → {vgoal, vvalid, vgo}   (Phase1 sim 注入；
//                                                          后续接 decision_fsm)
//         ↓ 统一
//     target(有效目标)/valid/go → state_machine
//         → trajectory_planner → pid_controller → virtual_motor → pos
//         → fault_detector(演示禁用, 仅 SW2) / seven_seg / beep / uart_telemetry
//   遥测保持 V1 主帧不变: [AA][state0..4][tgt][pos][chk]  (web Live 不退化)
//   action 编码(与 decision_fsm.o_cmd_action 一致): 0=STOP/2=FORWARD/3=LEFT/4=RIGHT
//     Phase1 STOP = 不发起新运动(当前运动继续到目标，随后 HOLD)。真正"立即冻结"
//     留待 Phase7/8 由 decision_fsm 的 EXECUTE/HOLD 语义实现 —— 这里如实标注。
//   参数与 top_system 一致(MS_DIV/VEL_DEG_S/TELEM_MS/蜂鸣音效)。
//------------------------------------------------------------------------------
module top_voice_robot #(
    parameter MS_DIV    = 50000,
    parameter VEL_DEG_S = 150,
    parameter TELEM_MS  = 100,
    parameter BEEP_DIG_FREQ = 2000,  parameter BEEP_DIG_DUR = 80,
    parameter BEEP_CLR_FREQ = 800,   parameter BEEP_CLR_DUR = 150,
    parameter BEEP_ENT_FREQ = 3000,  parameter BEEP_ENT_DUR = 120,
    parameter AW        = 24,        // PCM 位宽
    parameter INIT_MS   = 200,       // 上电等 ES8388 配置完成再启用窗口能量
    parameter CALIB_UART = 0,        // 1=校准固件: TX 改发能量/VAD 数值行(SSCOM 抓数)
    parameter VAD_TH_ON  = 24'h10_0000, // 实测2(2026-09-09): 近静音背景峰值偶达0x0D3A/说话峰值0x1C-0x65;
                                        // 取 TH_ON=0x100000(>背景0.21x裕量, 说话有声帧可越)
    parameter VAD_TH_OFF = 24'h0A_0000, // 退出须<TH_ON; 0x0A0000>静音典型峰值→结束可回落
    parameter VAD_HO     = 32,       // VAD 拖尾帧数(~170ms)
    parameter VOICE_EN   = 1,        // 1=语音链决策接入运动(VAD+owner+cmd→motion); 0=键盘/测试
    parameter CAP_UART   = 0,        // 1=语音真值采集: TX 每段发 MFCC 和/帧数(重建模板)
    parameter VDBG_UART  = 0,        // 0=发 [AA] 主遥测帧(web 数字孪生); 1=发 [AB] 语音调试帧
    parameter VOTE_N     = 8,        // (旧)片段投票帧数, 段级决策后顶层不再用
    // ---- 段级决策阈值(2026-09-10 闭环优先): 段均值 L1(→owner模板) 阈值, 见 rtl/seg_decide.v。
    //      真实板级数据: 属主全词段均值 max=4106(前进) < TH_OWN < 陌生人 min=4486;
    //      逐帧判定已废弃(owner/stranger 逐帧分布 3584~7424 完全重叠)。 ----
    parameter TH_OWN  = 4300,
    // ---- Phase2 双麦方向: L/R 能量比 > DIR_NUM/DIR_DEN 才算偏侧(默认 21/20=1.05×, 近距咪头敏感) ----
    parameter DIR_NUM = 21,
    parameter DIR_DEN = 20
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] col,
    output wire [3:0] row,
    input  wire       fault_sw,       // SW2：强制故障演示
    output wire       tx,             // 遥测串口
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led,
    output wire       buzzer_out,
    // ---- ES8388 数字接口 (Phase 2 迁入, J0 座) ----
    input  wire       aud_bclk,       // M6   codec→FPGA
    input  wire       aud_lrc,        // M7   codec→FPGA
    input  wire       aud_adcdat,     // R14  SDOUT codec→FPGA
    output wire       aud_mclk,       // N5   FPGA→codec 12.3MHz
    output wire       aud_scl,        // R12  I2C
    inout  wire       aud_sda         // R9   I2C
);
    // ---------- 线网声明 ----------
    wire tick_1ms;
    wire key_event;
    wire [3:0] key;
    wire [8:0] tgt9, entry_dummy;
    wire [9:0] target;               // 有效目标(键盘或语音)
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
    wire telem_tx;                   // [AA] 主帧串口(在校准固件时被数值行顶替)
    // 语音链 decision_fsm 输出(Phase3c 接入; 例化在后面, 此处仅声明供 seam 提前引用)
    wire dec_o_valid;
    wire [2:0] dec_o_act;
    wire [1:0] dir_w;               // 双麦方向(Phase2): 0中/1左/2右

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

    // KEY11=GO；KEY10=CLR/ACK
    reg go_d;
    always @(posedge clk) begin
        if (!rst_n) go_d <= 1'b0;
        else        go_d <= (key_event && key == 4'd11);
    end
    assign go_d_reg = go_d;
    assign clr_p    = key_event && key == 4'd10;

    // ------------------------------------------------------------------
    // ---- 语音命令缝 (Phase1: sim 注入; 后续 decision_fsm → 此处) ----
    //   v_act_valid = 1 拍有效; v_act: 2=FORWARD 3=LEFT 4=RIGHT 0/其它=STOP
    //   板上综合阶段 v_act 恒 0 → 纯键盘路径，与 top_system 逐位等价。
    // ------------------------------------------------------------------
    wire       v_act_valid;
    wire [2:0] v_act;
    assign v_act_valid = 1'b0;                 // TB 用 force 注入；板上为 0
    assign v_act       = 3'd0;

    // ---- 决策源(Phase3c): VOICE_EN=1 时由 decision_fsm 驱动；只取一次沿，防重复触发 ----
    reg ovalid_d;
    always @(posedge clk) ovalid_d <= dec_o_valid;
    wire dec_pulse      = VOICE_EN && dec_o_valid && !ovalid_d;
    wire dec_act_valid  = dec_pulse;          // 含 STOP(action 0): 段末 owner&&cmd 判定
    // Phase2 双麦方向: 命令=前进(action2) 时, 由声源方向定 左/右/前(3/4/2); 其它命令(action 0/3/4)不受方向影响
    wire [2:0] dir_act  = (dir_w==2'd1) ? 3'd3 : (dir_w==2'd2) ? 3'd4 : 3'd2;
    wire [2:0] act_eff  = (dec_o_act == 3'd2) ? dir_act : dec_o_act;
    wire       v_act_valid_eff = v_act_valid | dec_act_valid;
    wire [2:0] v_act_eff       = dec_act_valid ? act_eff : v_act;

    wire voice_cmd = v_act_valid_eff;         // action 0=STOP 亦为有效指令

    reg [9:0] vgoal;
    reg       vvalid;
    reg       vgo;                             // 延迟 1 拍 start(与 go_d 同构)
    always @(posedge clk) begin
        vgo <= 1'b0;
        if (!rst_n) begin vgoal <= 10'd90; vvalid <= 1'b0; end
        else if (key_event && key == 4'd11) vvalid <= 1'b0;   // 键盘 ENTER/GO 接管
        else if (clr_p)                     vvalid <= 1'b0;   // KEY10 清除
        else if (voice_cmd) begin
            // 2=FORWARD→90, 3=LEFT→0, 4=RIGHT→180, 0/其它=STOP→停当前位置
            vgoal  <= (v_act_eff == 3'd3) ? 10'd0
                    : (v_act_eff == 3'd4) ? 10'd180
                    : (v_act_eff == 3'd2) ? 10'd90
                    : pos;
            vvalid <= 1'b1;
            vgo    <= 1'b1;
        end
    end

    // ---- 统一目标/启动：vvalid 期间以语音目标为准，否则回到键盘目标 ----
    assign target    = vvalid ? vgoal : {1'b0, tgt9};
    wire fsm_valid   = tvalid | vvalid;
    wire fsm_go      = go_d_reg | vgo;

    // ---------- 状态机 ----------
    state_machine u_fsm (
        .clk(clk), .rst_n(rst_n),
        .target_valid(fsm_valid), .start(fsm_go),
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

    // ---------- 故障检测(演示禁用, 同 V1; 仅 SW2 手动) ----------
    fault_detector #(.STALL_MS(1500), .ERR_TOL(8)) u_fdet (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick_1ms), .run(1'b0),
        .pos(pos), .target(target), .ack(clr_p), .faulted(fdet)
    );
    assign fault_in = fault_sw;

    // ---------- 遥测 [AA][state][tgt][pos][chk] (V1 主帧, 不改) ----------
    uart_telemetry #(.TELEM_MS(TELEM_MS)) u_tele (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .state(st8), .target(target), .pos(pos),
        .tx(telem_tx), .fbyte(), .fbyte_ok()
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

    // ---------- 蜂鸣器反馈：数字/清除/确认 三种音效 (同 V1) ----------
    wire key_digit = key_event && (key <= 4'd9);
    wire key_clr   = key_event && (key == 4'd10);
    wire key_enter = key_event && (key == 4'd11);

    wire bz_digit, bz_clr, bz_enter;
    beep_gen #(.FREQ_HZ(BEEP_DIG_FREQ), .DUR_MS(BEEP_DIG_DUR)) u_bz_digit (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_digit), .buzzer(bz_digit)
    );
    beep_gen #(.FREQ_HZ(BEEP_CLR_FREQ), .DUR_MS(BEEP_CLR_DUR)) u_bz_clr (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_clr), .buzzer(bz_clr)
    );
    beep_gen #(.FREQ_HZ(BEEP_ENT_FREQ), .DUR_MS(BEEP_ENT_DUR)) u_bz_enter (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_enter), .buzzer(bz_enter)
    );
    // 无源蜂鸣器由方波驱动；同一时刻最多一个音效在响，直接按位或
    assign buzzer_out = bz_digit | bz_clr | bz_enter;

    //====================================================================
    // ES8388 真实采集链 (Phase 2, 自 top_audio 原样迁入; 不改 A1 已验证接线)
    //   PLL→MCLK; locked 作音频复位; I2C 配置(addr 0x11); I2S→L/R 24bit PCM;
    //   窗能量→LED 双声道电平条。pcm_l/pcm_r/pair_valid 留给 Phase3 feature_engine。
    //====================================================================
    reg [7:0] rst_cnt = 8'd0;
    always @(posedge clk)
        rst_cnt <= rst_cnt[7] ? rst_cnt : rst_cnt + 1'b1;

    wire locked;
    wire clk0_unused;
    clk_wiz_0 u_pll (
        .refclk  (clk),
        .reset   (~rst_cnt[7]),      // 上电复位 PLL
        .stdby   (1'b0),
        .extlock (locked),
        .clk0_out(clk0_unused),
        .clk1_out(aud_mclk)
    );
    wire rst_i = rst_n & locked;     // 音频链有效复位(低=复位)

    es8388_config u_cfg (
        .clk    (clk),
        .rst_n  (rst_i),
        .volume (2'b01),
        .aud_scl(aud_scl),
        .aud_sda(aud_sda),
        .inp_sel(3'b000),             // ADC 输入选 IN1(LIN1/RIN1)=咪头
        .ack_err()
    );

    wire [AW-1:0] pcm_l, pcm_r;
    wire pair_valid;
    audio_pcm_bridge #(.WL(AW), .LRC_LEFT(1'b0)) u_br (
        .sys_clk   (clk),
        .sys_rst_n (rst_i),
        .aud_bclk  (aud_bclk),
        .aud_lrc   (aud_lrc),
        .aud_adcdat(aud_adcdat),
        .pcm_l     (pcm_l),
        .pcm_r     (pcm_r),
        .pair_valid(pair_valid)
    );

    // 上电延时: 等 es8388_config 写完再启用窗能量(避免配置期噪声刷电平条)
    reg [11:0] ms_cnt;
    reg init_done;
    always @(posedge clk) begin
        if (!rst_i) begin
            ms_cnt <= 12'd0; init_done <= 1'b0;
        end else if (tick_1ms) begin
            if (!init_done) begin
                if (ms_cnt >= INIT_MS[11:0] - 1'b1) init_done <= 1'b1;
                else ms_cnt <= ms_cnt + 1'b1;
            end
        end
    end
    wire audio_rst_n = rst_i & init_done;

    // LED 状态指示(V1 风格): led[0]=有目标 led[1]=运动 led[2]=到位 led[3]=故障
    assign led = {4'b0000, faulted, at_target, moving, fsm_valid};

    // audio_calib_rpt(CALIB_UART=1 时)用 avg_l/r；主用 build 置 0 以免未定义
    wire [AW:0] avg_l, avg_r;
    assign avg_l = {AW+1{1'b0}};
    assign avg_r = {AW+1{1'b0}};

    //====================================================================
    // VAD (Phase3): 真实帧峰值 + 双阈值滞回 → vad_on。阈值经顶部参数按实测精调。
    //====================================================================
    wire vad_on, vad_rise_s, vad_fall_s;
    wire [AW:0] peak;
    audio_vad #(.TH_ON(VAD_TH_ON), .TH_OFF(VAD_TH_OFF), .HO_FRAMES(VAD_HO)) u_vad (
        .clk(clk), .rst_n(audio_rst_n), .sample_ok(pair_valid),
        .pcm_l(pcm_l), .pcm_r(pcm_r),
        .vad(vad_on), .vad_rise(vad_rise_s), .vad_fall(vad_fall_s), .peak(peak)
    );

    //====================================================================
    // 语音感知链 (Phase3c/4 → 段级决策 2026-09-10): 帧控制器 → feature_engine(MFCC)
    //   → seg_decide(段内累加→段均值): owner 闸(段均值 L1 < TH_OWN) + cmd argmin(4 模板)
    //   → decision_fsm: owner&&cmd → dec_o_valid/dec_o_act(0停/2前/3左/4右)
    //   VOICE_EN=1 时 dec_o_* 驱动运动 seam(取沿)。
    //   注: 模板为参数常量内嵌(seg_decide.v 默认值, TD 不支持 $readmemh), 由 data/*.mem 离线生成。
    //====================================================================
    wire        fc_ss, fc_pv;
    wire signed [AW-1:0] fc_pcm;
    wire fe_busy, fe_valid, fe_done;
    wire [3:0] fe_index;
    wire signed [15:0] fe_data;
    v2_frame_ctrl #(.AW(AW)) u_fc (
        .clk(clk), .rst_n(audio_rst_n), .sample_ok(pair_valid), .pcm_l(pcm_l),
        .speech(vad_on), .fe_busy(fe_busy),
        .frame_start(fc_ss), .fe_pcm_valid(fc_pv), .fe_pcm(fc_pcm), .frames_sent()
    );
    feature_engine u_fe (
        .clk(clk), .rst_n(audio_rst_n), .enable(1'b1),
        .frame_start(fc_ss), .pcm_valid(fc_pv), .pcm_data(fc_pcm),
        .busy(fe_busy), .feature_valid(fe_valid), .feature_index(fe_index),
        .feature_data(fe_data), .frame_done(fe_done)
    );

    // 段级决策(替代逐帧 Who/What): 段内累加→段均值→owner闸+cmd argmin, 见 rtl/seg_decide.v
    wire        seg_own, seg_done;
    wire [1:0]  seg_cmd;
    wire [15:0] seg_mean;            // 段均值 L1(→owner模板), 调试用
    seg_decide #(.TH_OWN(TH_OWN)) u_segdec (
        .clk(clk), .rst_n(audio_rst_n),
        .fe_valid(fe_valid), .fe_index(fe_index), .fe_data(fe_data),
        .vad(vad_on), .vad_rise(vad_rise_s), .vad_fall(vad_fall_s),
        .owner_valid(seg_own), .seg_done(seg_done), .cmd_id(seg_cmd), .own_mean(seg_mean)
    );
    // decision: 段末(seg_done) owner&&cmd → action
    decision_fsm u_dec (
        .clk(clk), .rst_n(audio_rst_n), .in_valid(seg_done),
        .in_vad(1'b0), .in_auth(1'b0), .in_dir(2'd0),
        .i_owner_valid(seg_own), .i_cmd_decision_valid(1'b1), .i_cmd_id(seg_cmd),
        .action_valid(), .action(),
        .o_cmd_valid(dec_o_valid), .o_cmd_action(dec_o_act)
    );
    // Phase2 双麦方向: VAD 段内 L/R 幅度能量比 → 左/中/右(dir_w), 供前进命令选向
    dir_energy #(.NUM(DIR_NUM), .DEN(DIR_DEN)) u_dir (
        .clk(clk), .rst_n(audio_rst_n),
        .sample_ok(pair_valid), .pcm_l(pcm_l), .pcm_r(pcm_r),
        .vad(vad_on), .vad_rise(vad_rise_s), .vad_fall(vad_fall_s),
        .dir(dir_w), .dir_valid()
    );

    //====================================================================
    // 校准固件: CALIB_UART=1 时 TX 改发能量/VAD 数值行(SSCOM 抓静音/说话/拍手
    // 数值 → 据此定 VAD_TH_ON/TH_OFF)。默认 0: TX 保持 [AA] 主帧不动。
    //====================================================================
    wire calib_tx;
    generate
        if (CALIB_UART == 1) begin : g_calib
            audio_calib_rpt #(.PERIOD_MS(200)) u_calib (
                .clk(clk), .rst_n(audio_rst_n), .tick_1ms(tick_1ms),
                .pk(peak[23:0]), .avg_l(avg_l[23:0]), .avg_r(avg_r[23:0]),
                .vad_in(vad_on), .tx(calib_tx)
            );
        end else begin : g_nocal
            assign calib_tx = 1'b1;
        end
    endgenerate
    // CAP_UART=1: 每段语音发 MFCC 和/帧数(板上真值采集重建模板)；优先级高于 CALIB
    wire cap_tx;
    generate
        if (CAP_UART == 1) begin : g_cap
            voice_cap_rpt u_cap (
                .clk(clk), .rst_n(audio_rst_n),
                .fe_valid(fe_valid), .fe_index(fe_index), .fe_data(fe_data),
                .vad(vad_on), .vad_rise(vad_rise_s), .vad_fall(vad_fall_s),
                .tx(cap_tx)
            );
        end else begin : g_nocap
            assign cap_tx = 1'b1;
        end
    endgenerate
    // VDBG_UART=1: TX 改发 0xAB 语音调试帧(每 200ms, bring-up H3-H6 观察用)。
    //   内容: [AB][vad][mfcc_any][owner][cmd][action][score][chk]，不改语音算法/数据路径。
    //   [AA] 主帧逻辑不受影响——本 build 只是把 TX 改接到调试帧, 默认 build(VDBG=0)照发 [AA]。
    wire vdbg_tx;
    generate
        if (VDBG_UART == 1) begin : g_vdbg
            voice_dbg_rpt u_vdbg (
                .clk(clk), .rst_n(audio_rst_n), .tick_1ms(tick_1ms),
                .vad(vad_on), .mfcc(fe_valid), .owner(seg_own), .fr_match(seg_done),
                .cmd_id(seg_cmd), .action(act_eff), .score(seg_mean[15:8]),
                .tx(vdbg_tx)
            );
        end else begin : g_novdbg
            assign vdbg_tx = 1'b1;
        end
    endgenerate
    assign tx = (VDBG_UART == 1) ? vdbg_tx
              : (CAP_UART == 1) ? cap_tx
              : (CALIB_UART == 1) ? calib_tx : telem_tx;
endmodule
