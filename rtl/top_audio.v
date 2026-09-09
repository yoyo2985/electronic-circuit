//------------------------------------------------------------------------------
// top_audio.v   A1 音频采集最小系统（独立工程，不动 V1 闭环）
//
//   ES8388(codec 主时钟) ──I2S──> audio_pcm_bridge ──L/R PCM──> audio_energy
//        └──── MCLK(12.3MHz) 由 PLL(clk_wiz_0) 从 50MHz 产生
//   energy 每 ~21ms 出一窗平均 → LED 双声道电平(左=led[7:4],右=led[3:0])
//                                    → audio_rpt 经 UART 发 "Lxxxx Rxxxx\n"
//
// 验收（捂/对某只咪头说话）：
//   ① 对 mic1 说话 → led[7:4] 亮、led[3:0] 基本不动；
//   ② 对 mic2 说话 → led[3:0] 亮、led[7:4] 不动  ← 证明 L/R 两路独立。
//   ③ 串口终端看到左右能量数值实时变化。
//
// 若 L/R 与预期反了：不改 bridge，在顶层交换 u_br 的 pcm_l/pcm_r 即可。
//------------------------------------------------------------------------------
module top_audio #(
    parameter AW       = 24,
    parameter WIN_LOG2 = 10,          // 1024 帧 ≈21.3ms
    parameter INIT_MS  = 200,         // 上电等 ES8388 配置完成再启用显示/上报
    parameter BAUD_TICKS = 434
) (
    input  wire sys_clk,              // 50MHz, R7
    input  wire sys_rst_n,            // SW0 拨上=运行, A9

    // ES8388 数字接口
    input  wire aud_bclk,             // M6   codec→FPGA
    input  wire aud_lrc,              // M7   codec→FPGA
    input  wire aud_adcdat,           // R14  SDOUT codec→FPGA
    output wire aud_mclk,             // N5   FPGA→codec 12.3MHz
    output wire aud_scl,              // R12  I2C
    inout  wire aud_sda,              // R9   I2C

    output wire tx,                   // UART 115200, D12
    output wire [7:0] led             // 双声道电平条
);

    //===========================================================
    // PLL → MCLK；locked 作全局有效复位
    //===========================================================
    reg  [7:0] rst_cnt = 8'd0;
    always @(posedge sys_clk)
        rst_cnt <= rst_cnt[7] ? rst_cnt : rst_cnt + 1'b1;

    wire locked;
    wire clk0_unused;
    clk_wiz_0 u_pll (
        .refclk  (sys_clk),
        .reset   (~rst_cnt[7]),       // 上电复位 PLL
        .stdby   (1'b0),
        .extlock (locked),
        .clk0_out(clk0_unused),
        .clk1_out(aud_mclk)
    );

    wire rst_i = sys_rst_n & locked;  // 供配置链/bridge（低=复位）

    //===========================================================
    // ES8388 I2C 配置（复用官方 rtl/audio/* 配置链）
    //===========================================================
    es8388_config u_cfg (
        .clk    (sys_clk),
        .rst_n  (rst_i),
        .volume (2'b01),              // 固定中等增益
        .aud_scl(aud_scl),
        .aud_sda(aud_sda),
        .inp_sel(3'b000)              // ADC 输入选 IN1(LIN1/RIN1)=咪头，勿悬空
    );

    //===========================================================
    // I2S 接收 + 声道分离 + 跨时钟 → L/R PCM 对
    //===========================================================
    wire [AW-1:0] pcm_l, pcm_r;
    wire pair_valid;
    audio_pcm_bridge #(.WL(AW), .LRC_LEFT(1'b0)) u_br (
        .sys_clk   (sys_clk),
        .sys_rst_n (rst_i),
        .aud_bclk  (aud_bclk),
        .aud_lrc   (aud_lrc),
        .aud_adcdat(aud_adcdat),
        .pcm_l     (pcm_l),
        .pcm_r     (pcm_r),
        .pair_valid(pair_valid)
    );

    //===========================================================
    // 上电延时：等 es8388_config 写完再启用窗口/上报，避免配置前噪声刷屏
    //===========================================================
    wire tick_1ms;
    clock_enable #(.MS_DIV(50000)) u_ce (
        .clk(sys_clk), .rst_n(rst_i), .tick_1ms(tick_1ms)
    );
    reg [11:0] ms_cnt;
    reg init_done;
    always @(posedge sys_clk) begin
        if (!rst_i) begin
            ms_cnt <= 12'd0;
            init_done <= 1'b0;
        end else if (tick_1ms) begin
            if (ms_cnt >= INIT_MS[11:0] - 1'b1) init_done <= 1'b1;
            else ms_cnt <= ms_cnt + 1'b1;
        end
    end
    wire audio_rst_n = rst_i & init_done;   // 能量/上报的复位

    //===========================================================
    // 窗口能量
    //===========================================================
    wire [AW:0] avg_l, avg_r;
    wire win_done;
    audio_energy #(.AW(AW), .WIN_LOG2(WIN_LOG2)) u_ene (
        .clk(sys_clk), .rst_n(audio_rst_n), .sample_ok(pair_valid),
        .pcm_l(pcm_l), .pcm_r(pcm_r),
        .avg_l(avg_l), .avg_r(avg_r), .win_done(win_done)
    );

    //===========================================================
    // VAD 语音活动检测（B1）：有语音→speech_on=1，串口 V 字段显示
    //   阈值等用 audio_vad 默认；等拿到真实麦克风数据再精调
    //===========================================================
    wire speech_on, vad_rise, vad_fall;
    audio_vad u_vad (
        .clk(sys_clk), .rst_n(audio_rst_n), .sample_ok(pair_valid),
        .pcm_l(pcm_l), .pcm_r(pcm_r),
        .vad(speech_on), .vad_rise(vad_rise), .vad_fall(vad_fall),
        .peak()
    );

    //===========================================================
    // LED 双声道电平：avg 取最高置位位 → 对数式 4 级指示条
    //   led[7:4]=左，led[3:0]=右（低=灭，逐级亮起）
    //===========================================================
    function [3:0] meter4(input [AW:0] v);
        integer q;
        reg [7:0] tb;
        begin
            tb = 0;
            for (q = 0; q <= AW; q = q + 1)
                if (v[q]) tb = q;               // 循环后 tb=最高置位
            if      (tb >= AW-3) meter4 = 4'b1111;
            else if (tb >= AW-8) meter4 = 4'b0111;
            else if (tb >= AW-13) meter4 = 4'b0011;
            else if (tb >= AW-18) meter4 = 4'b0001;
            else                  meter4 = 4'b0000;
        end
    endfunction
    assign led[7:4] = meter4(avg_l);
    assign led[3:0] = meter4(avg_r);

    //===========================================================
    // 串口状态上报：每 0.5s 无条件发 "Pxxxx Lxxxx Rxxxx\n"
    //   P = 该 0.5s 收到的音频帧数（≈24000=codec 在流；≈0=codec 没出帧）
    //   L/R = 该 0.5s 内 |PCM| 的峰值（>0xFFFF 饱和为 FFFF），比 avg 灵敏，
    //         轻敲咪头/说话都应能看到数值。
    // 调试期用；等 A1 验收正常后可按需换回按窗细报的 audio_rpt。
    //===========================================================
    wire signed [AW-1:0] sl2 = pcm_l;
    wire signed [AW-1:0] sr2 = pcm_r;
    wire [AW-1:0] mag_l = sl2[AW-1] ? (~sl2 + 1'b1) : sl2[AW-1:0];
    wire [AW-1:0] mag_r = sr2[AW-1] ? (~sr2 + 1'b1) : sr2[AW-1:0];
    reg [AW-1:0] pk_l, pk_r;
    reg [15:0]   pk_o_l, pk_o_r;
    reg [9:0]    pms;
    always @(posedge sys_clk) begin
        if (!audio_rst_n) begin
            pk_l <= {AW{1'b0}}; pk_r <= {AW{1'b0}};
            pk_o_l <= 16'd0; pk_o_r <= 16'd0; pms <= 10'd0;
        end else begin
            if (pair_valid) begin
                if (mag_l > pk_l) pk_l <= mag_l;
                if (mag_r > pk_r) pk_r <= mag_r;
            end
            if (tick_1ms) begin
                if (pms == 10'd499) begin
                    // 与 audio_status 同 500ms 边界锁存（饱和显示）
                    pk_o_l <= (pk_l[AW-1:16] != 0) ? 16'hFFFF : pk_l[15:0];
                    pk_o_r <= (pk_r[AW-1:16] != 0) ? 16'hFFFF : pk_r[15:0];
                    pk_l <= {AW{1'b0}}; pk_r <= {AW{1'b0}};
                    pms <= 10'd0;
                end else begin
                    pms <= pms + 1'b1;
                end
            end
        end
    end
    audio_status #(.BAUD_TICKS(BAUD_TICKS), .PERIOD_MS(500)) u_st (
        .clk(sys_clk), .rst_n(audio_rst_n), .tick_1ms(tick_1ms),
        .frame_ok(pair_valid),
        .e_l(pk_o_l), .e_r(pk_o_r), .vad_in(speech_on), .tx(tx)
    );

endmodule
