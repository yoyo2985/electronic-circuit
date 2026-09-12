//------------------------------------------------------------------------------
// top_cap.v  Phase5a 纯采集最小顶层：ES8388 → PCM → VAD → 帧控 → MFCC → 每段打印
//   目的：在板上采集真实语音段 MFCC 和/帧数(经 UART)，供 PC 重建 owner/命令模板。
//   不含运动/键盘/声纹/决策 → 面积小、聚焦 feature_engine 真实面积。
//   行格式同 voice_cap_rpt: 'M' + count(8hex) + 13×sum(8hex) + '\n'
//   注意: 系数表 $readmemh 已用绝对路径；TD 综合对 $readmemh 初值是否成为 ROM 内容
//   需在板上验证(见报告), 若 ROM 内容为 0/x 会在此暴露。
//------------------------------------------------------------------------------
module top_cap #(
    parameter AW        = 24,
    parameter INIT_MS   = 200,
    parameter VAD_TH_ON  = 24'h10_0000,
    parameter VAD_TH_OFF = 24'h0A_0000,
    parameter VAD_HO     = 32
) (
    input  wire       clk,            // R7 50MHz
    input  wire       rst_n,          // A9
    input  wire       aud_bclk,       // M6
    input  wire       aud_lrc,        // M7
    input  wire       aud_adcdat,     // R14
    output wire       aud_mclk,       // N5
    output wire       aud_scl,        // R12
    inout  wire       aud_sda,        // R9
    output wire       tx              // D12
);
    // ---- PLL→MCLK; locked→音频复位域 ----
    reg [7:0] rst_cnt = 8'd0;
    always @(posedge clk) rst_cnt <= rst_cnt[7] ? rst_cnt : rst_cnt + 1'b1;
    wire locked, clk0_unused;
    clk_wiz_0 u_pll (
        .refclk(clk), .reset(~rst_cnt[7]), .stdby(1'b0),
        .extlock(locked), .clk0_out(clk0_unused), .clk1_out(aud_mclk));
    wire rst_i = rst_n & locked;

    es8388_config u_cfg (
        .clk(clk), .rst_n(rst_i), .volume(2'b01),
        .aud_scl(aud_scl), .aud_sda(aud_sda), .inp_sel(3'b000), .ack_err());

    wire [AW-1:0] pcm_l, pcm_r;
    wire pair_valid;
    audio_pcm_bridge #(.WL(AW), .LRC_LEFT(1'b0)) u_br (
        .sys_clk(clk), .sys_rst_n(rst_i),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .pcm_l(pcm_l), .pcm_r(pcm_r), .pair_valid(pair_valid));

    // 1ms tick + init 延时
    wire tick_1ms;
    clock_enable u_ce (.clk(clk), .rst_n(rst_i), .tick_1ms(tick_1ms));
    reg [11:0] ms_cnt; reg init_done;
    always @(posedge clk) begin
        if (!rst_i) begin ms_cnt <= 0; init_done <= 0; end
        else if (tick_1ms) begin
            if (!init_done) begin
                if (ms_cnt >= INIT_MS[11:0] - 1) init_done <= 1; else ms_cnt <= ms_cnt + 1;
            end
        end
    end
    wire a_rst_n = rst_i & init_done;

    // VAD
    wire vad_on, vad_rise, vad_fall;
    wire [AW:0] peak;
    audio_vad #(.TH_ON(VAD_TH_ON), .TH_OFF(VAD_TH_OFF), .HO_FRAMES(VAD_HO)) u_vad (
        .clk(clk), .rst_n(a_rst_n), .sample_ok(pair_valid),
        .pcm_l(pcm_l), .pcm_r(pcm_r),
        .vad(vad_on), .vad_rise(vad_rise), .vad_fall(vad_fall), .peak(peak));

    // 帧控 + MFCC
    wire fc_ss, fc_pv;
    wire signed [AW-1:0] fc_pcm;
    wire fe_busy, fe_valid, fe_done;
    wire [3:0] fe_index;
    wire signed [15:0] fe_data;
    v2_frame_ctrl #(.AW(AW)) u_fc (
        .clk(clk), .rst_n(a_rst_n), .sample_ok(pair_valid), .pcm_l(pcm_l),
        .speech(vad_on), .fe_busy(fe_busy),
        .frame_start(fc_ss), .fe_pcm_valid(fc_pv), .fe_pcm(fc_pcm), .frames_sent());
    feature_engine u_fe (
        .clk(clk), .rst_n(a_rst_n), .enable(1'b1),
        .frame_start(fc_ss), .pcm_valid(fc_pv), .pcm_data(fc_pcm),
        .busy(fe_busy), .feature_valid(fe_valid), .feature_index(fe_index),
        .feature_data(fe_data), .frame_done(fe_done));

    // 每段 MFCC 采集打印
    voice_cap_rpt u_cap (
        .clk(clk), .rst_n(a_rst_n),
        .fe_valid(fe_valid), .fe_index(fe_index), .fe_data(fe_data),
        .vad(vad_on), .vad_rise(vad_rise), .vad_fall(vad_fall),
        .tx(tx));
endmodule
