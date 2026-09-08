//------------------------------------------------------------------------------
// decision_fsm.v   决策：VAD + 声纹门控(owner) + 方向 → 动作
//   action: 0=IDLE 1=REJECT(非主人忽略) 2=FORWARD 3=LEFT 4=RIGHT
//   语音段内一旦 in_auth=1 即锁存 owner 到本段结束(无语音清)。与 py 同规则。
//------------------------------------------------------------------------------
module decision_fsm (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              in_valid,
    input  wire              in_vad,
    input  wire              in_auth,
    input  wire [1:0]        in_dir,
    output reg               action_valid,
    output reg  [2:0]        action
);
    reg auth_l;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            auth_l       <= 1'b0;
            action_valid <= 1'b0;
            action       <= 3'd0;
        end else begin
            action_valid <= 1'b0;
            if (in_valid) begin
                if (!in_vad) begin
                    auth_l <= 1'b0;
                    action <= 3'd0;             // IDLE
                end else begin
                    if (in_auth) auth_l <= 1'b1;
                    if (!auth_l && !in_auth) begin
                        action <= 3'd1;         // REJECT
                    end else begin
                        case (in_dir)
                            2'd1: action <= 3'd3;   // LEFT
                            2'd2: action <= 3'd4;   // RIGHT
                            default: action <= 3'd2; // FORWARD
                        endcase
                    end
                end
                action_valid <= 1'b1;
            end
        end
    end
endmodule
