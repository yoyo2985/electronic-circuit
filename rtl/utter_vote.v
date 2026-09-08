//------------------------------------------------------------------------------
// utter_vote.v   B5.7 片段级多数投票（frame→utterance）
//   输入 speaker_verify 每帧 frame_valid/frame_match；滑动窗口 VOTE_N：
//   acc 为最近 ≤VOTE_N 帧中 match=1 的帧数；自第 VOTE_N 帧起每帧出一个判决：
//   decision_valid + owner = (acc>=MIN_MATCH)。
//   · 不足 VOTE_N 帧(valid 帧不够)不判决；单帧 match 不会单独触发 owner。
//   · 不改 vtmpl L1 定义、不改 B5.3 语义。
//------------------------------------------------------------------------------
module utter_vote #(
    parameter VOTE_N    = 8,
    parameter MIN_MATCH = 5
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             frame_valid,
    input  wire             frame_match,
    output reg              decision_valid,
    output reg              owner_valid,
    output reg  [7:0]       frames_seen
);
    localparam ACW = $clog2(VOTE_N + 1);
    reg [VOTE_N-1:0] history;
    reg [ACW-1:0]   acc;
    reg [ACW-1:0]   newacc;
    reg             remove;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            history       <= {VOTE_N{1'b0}};
            acc           <= {ACW{1'b0}};
            newacc        <= {ACW{1'b0}};
            remove        <= 1'b0;
            decision_valid<= 1'b0;
            owner_valid   <= 1'b0;
            frames_seen   <= 8'd0;
        end else begin
            decision_valid <= 1'b0;
            if (frame_valid) begin
                remove  = history[VOTE_N-1];       // 被顶出的最旧帧
                history <= {history[VOTE_N-2:0], frame_match};
                newacc  = acc - remove + frame_match;
                acc     <= newacc;
                if (frames_seen >= VOTE_N) begin
                    owner_valid    <= (newacc >= MIN_MATCH) ? 1'b1 : 1'b0;
                    decision_valid <= 1'b1;
                end
                frames_seen <= (frames_seen >= 8'd255) ? 8'd255 : frames_seen + 8'd1;
            end
        end
    end

endmodule
