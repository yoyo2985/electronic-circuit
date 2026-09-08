//------------------------------------------------------------------------------
// audio_vad.v   语音活动检测（VAD）
//   以 L/R PCM 为输入，每 F_LEN(=2^F_LEN_LOG2) 个立体声采样为一帧(~5.3ms)：
//     · 帧特征 = 帧内 max(|L|,|R|) 峰值
//     · 双阈值滞回：peak>=TH_ON 进入语音；peak<TH_OFF 才允许退出（防抖）
//     · 拖尾 HO_FRAMES：退出前需连续若干低帧，语音内小停顿不切段
//   输出 vad 电平 + vad_rise/vad_fall 起止沿（供后续分段采集语音段做声纹/指令）。
//   TH_ON/TH_OFF/HO_FRAMES 都是 parameter：等拿到真实麦克风录音后只改顶层参数精调。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module audio_vad #(
    parameter AW         = 24,
    parameter F_LEN_LOG2 = 8,          // 256 帧 ≈ 5.3ms
    parameter TH_ON      = 24'h04_0000, // 帧峰值>=此进入语音（默认 2^18；按实录音调）
    parameter TH_OFF     = 24'h01_0000, // 帧峰值<此才允许退出（须 TH_OFF<TH_ON）
    parameter HO_FRAMES  = 32           // 拖尾：连续多少低帧才判定结束(~170ms)
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          sample_ok,     // 每立体声对 1 拍（audio_pcm_bridge.pair_valid）
    input  wire [AW-1:0] pcm_l,
    input  wire [AW-1:0] pcm_r,
    output reg           vad,           // 1=正在说话
    output reg           vad_rise,      // 语音开始（1 拍）
    output reg           vad_fall,      // 语音结束（1 拍）
    output reg  [AW:0]   peak           // 最近一帧的峰值（调试/显示用）
);

    localparam FLEN = (1 << F_LEN_LOG2);
    localparam CNT_W = F_LEN_LOG2;
    localparam HO_W  = (HO_FRAMES <= 1) ? 1 : $clog2(HO_FRAMES);

    // 组合：24 位有符号 → 25 位幅度，取两声道较大者
    wire signed [AW-1:0] sl = pcm_l;
    wire signed [AW-1:0] sr = pcm_r;
    wire signed [AW:0]   el = {sl[AW-1], sl};
    wire signed [AW:0]   er = {sr[AW-1], sr};
    wire [AW:0] mag_l = el[AW] ? (~el + 1'b1) : el[AW:0];
    wire [AW:0] mag_r = er[AW] ? (~er + 1'b1) : er[AW:0];
    wire [AW:0] mx    = (mag_l > mag_r) ? mag_l : mag_r;

    //===========================================================
    // 分帧求峰值
    //===========================================================
    reg  [CNT_W-1:0] cnt;
    reg  [AW:0]      pk;               // 帧内已见最大值
    reg              feat_ok;          // 帧边界脉冲

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt     <= {CNT_W{1'b0}};
            pk      <= {AW+1{1'b0}};
            feat_ok <= 1'b0;
            peak    <= {AW+1{1'b0}};
        end else begin
            feat_ok <= 1'b0;
            if (sample_ok) begin
                if (cnt == FLEN[CNT_W-1:0] - 1'b1) begin
                    // 本帧最后一拍：峰值计入当前样本
                    peak    <= (mx > pk) ? mx : pk;
                    feat_ok <= 1'b1;
                    pk      <= {AW+1{1'b0}};
                    cnt     <= {CNT_W{1'b0}};
                end else begin
                    if (mx > pk) pk <= mx;
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

    //===========================================================
    // 滞回 + 拖尾 状态判定（在 feat_ok 脉冲上更新）
    //===========================================================
    reg [HO_W-1:0] ho;

    always @(posedge clk) begin
        if (!rst_n) begin
            vad      <= 1'b0;
            vad_rise <= 1'b0;
            vad_fall <= 1'b0;
            ho       <= {HO_W{1'b0}};
        end else begin
            vad_rise <= 1'b0;
            vad_fall <= 1'b0;
            if (feat_ok) begin
                if (!vad) begin
                    if (peak >= TH_ON) begin
                        vad      <= 1'b1;
                        vad_rise <= 1'b1;
                        ho       <= {HO_W{1'b0}};
                    end
                end else begin
                    if (peak < TH_OFF) begin
                        if (ho == HO_FRAMES[HO_W-1:0] - 1'b1) begin
                            vad      <= 1'b0;   // 连续 HO_FRAMES 个低帧 → 结束
                            vad_fall <= 1'b1;
                            ho       <= {HO_W{1'b0}};
                        end else begin
                            ho <= ho + 1'b1;
                        end
                    end else begin
                        ho <= {HO_W{1'b0}};     // 仍足够响，重置拖尾计数
                    end
                end
            end
        end
    end

endmodule
