//------------------------------------------------------------------------------
// cmd_vote.v   KWS 命令多数投票（滑动窗口众数）
//   输入 cmd_valid/cmd_id(每帧匹配结果)；窗口 VOTE_N；窗口满后每帧输出众数
//   （并列取小 id）。统计忽略 no_match 之外？默认统计 0..NUM-1。
//------------------------------------------------------------------------------
module cmd_vote #(
    parameter VOTE_N = 8,
    parameter NUM    = 4
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             cmd_valid,
    input  wire [1:0]       cmd_id,
    output reg              decision_valid,
    output reg  [1:0]       cmd_id_out,
    output reg  [7:0]       frames_seen
);
    reg [1:0] q[0:VOTE_N-1];
    integer i, j, best, cnt, cand;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            decision_valid <= 1'b0;
            cmd_id_out     <= 2'd0;
            frames_seen    <= 8'd0;
            for (i = 0; i < VOTE_N; i = i + 1) q[i] <= 2'd0;
        end else begin
            decision_valid <= 1'b0;
            if (cmd_valid) begin
                // 前移窗口，新 id 入末位
                for (i = 0; i < VOTE_N - 1; i = i + 1) q[i] <= q[i+1];
                q[VOTE_N-1] <= cmd_id;
                if (frames_seen >= VOTE_N) begin
                    best = 0; cand = 0;
                    for (j = 0; j < NUM; j = j + 1) begin
                        cnt = 0;
                        for (i = 0; i < VOTE_N; i = i + 1)
                            if (q[i] == j) cnt = cnt + 1;
                        if (cnt > best) begin best = cnt; cand = j; end
                    end
                    cmd_id_out     <= cand[1:0];
                    decision_valid <= 1'b1;
                end
                frames_seen <= (frames_seen >= 8'd255) ? 8'd255 : frames_seen + 8'd1;
            end
        end
    end

endmodule
