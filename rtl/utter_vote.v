//------------------------------------------------------------------------------
// utter_vote.v   B5.7c 段级累计投票（frame→utterance，替代滑动 8 帧多数决）
//   背景(2026-09-10 板上数据): 手机录音模板 vs 板载麦通道差 → 单帧匹配率仅≈0.1%,
//   滑动"8 帧取 5"实际永不触发。改为"整段累计": VAD 段内累计匹配帧数,
//   累计 ≥ MIN_MATCH 即认定 owner(段内粘性, 不再要求连续窗口凑多数)。
//   判别力依据(离线 utterance-mean): owner 1224±581 vs imp 2098±1224, 明显优于
//   帧级 3134 vs 3538 的大幅重叠 —— 聚合是有效的判别增益。
//   时序: vad=1 段内逐帧累计(frames_seen=段内帧数); vad=0 段末 decision_valid
//   脉冲汇报本段判决并复位(下一段重计)。帧流仅在 VAD 期间存在(v2_frame_ctrl
//   以 speech 门控), 故"段"即连续帧流。
//------------------------------------------------------------------------------
module utter_vote #(
    parameter MIN_MATCH = 5      // 段内累计匹配帧数达到即 owner=1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             vad,          // 段信号(VAD 电平)
    input  wire             frame_valid,
    input  wire             frame_match,
    output reg              decision_valid, // 段末 1 拍: 本段 owner 判决
    output reg              owner_valid,    // 段内粘性: 已认定 owner
    output reg  [7:0]       frames_seen     // 段内帧数(调试)
);
    reg [8:0] acc_n;                   // 组合: 含当前帧的段内匹配计数
    reg [7:0] acc;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            acc <= 8'd0; decision_valid <= 1'b0; owner_valid <= 1'b0; frames_seen <= 8'd0;
        end else begin
            decision_valid <= 1'b0;
            acc_n = acc + ((frame_valid && frame_match && acc != 8'd255) ? 9'd1 : 9'd0);
            if (vad) begin
                if (frame_valid) begin
                    acc         <= acc_n[7:0];
                    frames_seen <= (frames_seen >= 8'd255) ? 8'd255 : frames_seen + 8'd1;
                end
                if (acc_n >= MIN_MATCH[8:0]) owner_valid <= 1'b1;
            end else begin
                // 段末: 汇报本段判决并复位
                decision_valid <= owner_valid;
                acc <= 8'd0; owner_valid <= 1'b0; frames_seen <= 8'd0;
            end
        end
    end

endmodule
