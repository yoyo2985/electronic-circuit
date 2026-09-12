//------------------------------------------------------------------------------
// v2_frame_ctrl.v  语音帧控制器(Phase3b)：把 audio_pcm_bridge 的真实 L 声道
//   PCM 流按 feature_engine 的输入协议喂成连续 MFCC 帧。
//
//   feature_engine 时序(实测代码):
//     · S_WAIT 下 frame_start 一拍 → busy=1 → S_CAPT；之后需恰好 64 个 pcm_valid
//       (每拍一个采样) → S_WIN..S_DCT → S_DONE(busy=0, frame_done=1) → S_WAIT。
//     · 引擎忙(含捕获与计算)期间不接受新 frame_start，也不读 pcm_valid。
//   (关键) 与 frame_start 同拍的 pcm_valid 会被 S_WAIT 忽略 → 首采样必须
//   frame_start 之后一拍再送。
//
//   控制器：speech(VAD) 为高且引擎空闲时开新帧；把紧接其后的 64 个采样(一拍一个)
//   送给引擎；引擎计算期覆盖掉的少量采样丢弃(每帧约几采样, 可忽略)。VAD 期间持续
//   出帧 → 供 speaker_verify/cmd_matcher 的 8 帧投票。
//   复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module v2_frame_ctrl #(
    parameter AW   = 24,
    parameter N    = 64,
    parameter LOGN = 6
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_ok,          // audio_pcm_bridge.pair_valid (~48k)
    input  wire signed [AW-1:0] pcm_l,            // 取左声道(L)；R 留给方向
    input  wire               speech,             // audio_vad.vad
    input  wire               fe_busy,            // feature_engine.busy
    output reg                frame_start,        // → feature_engine
    output reg                fe_pcm_valid,
    output reg  signed [AW-1:0] fe_pcm,
    output reg  [31:0]        frames_sent         // 调试/统计
);

    localparam S_IDLE = 2'd0, S_PEND = 2'd1, S_RUN = 2'd2;
    reg [1:0]  st;
    reg [LOGN-1:0] cnt;

    always @(posedge clk) begin
        frame_start <= 1'b0;
        fe_pcm_valid <= 1'b0;
        if (!rst_n) begin
            st <= S_IDLE; cnt <= {LOGN{1'b0}}; frames_sent <= 32'd0; fe_pcm <= {AW{1'b0}};
        end else begin
            case (st)
                S_IDLE: begin
                    if (speech && !fe_busy) begin
                        frame_start <= 1'b1;     // 先拉一帧启动
                        st <= S_PEND;
                    end
                end
                S_PEND: begin
                    if (sample_ok) begin         // 首采样(frame_start 已过一拍)
                        fe_pcm_valid <= 1'b1;
                        fe_pcm       <= pcm_l;
                        cnt <= {{LOGN-1{1'b0}}, 1'b1};   // 已送 1
                        st  <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (sample_ok) begin
                        fe_pcm_valid <= 1'b1;
                        fe_pcm       <= pcm_l;
                        if (cnt == N[LOGN-1:0] - 1'b1) begin
                            cnt <= {LOGN{1'b0}};
                            st  <= S_IDLE;
                            frames_sent <= frames_sent + 32'd1;
                        end else begin
                            cnt <= cnt + {{LOGN-1{1'b0}}, 1'b1};
                        end
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
