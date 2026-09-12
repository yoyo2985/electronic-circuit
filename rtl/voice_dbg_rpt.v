//------------------------------------------------------------------------------
// voice_dbg_rpt.v  语音调试帧：每 PERIOD_MS 经 TX 发一帧 [AB][vad][mfcc][owner][cmd][action][score][chk]
//   8 字节, 与 [AA] 主帧同链(115200)。仅调试观察, 不改语音算法/数据路径。
//     [0]0xAB [1]vad [2]mfcc_any [3]{0,fr_any,owner} [4]cmd_id [5]action [6]score [7]chk=XOR 前7字节
//   mfcc_any/fr_any 为脉冲输入: 自上次上报以来任一特征帧/任一单帧匹配, 模块内锁存、上报时清。
//   score 由顶层提供(spk_dist 高位摘要, 如 spk_dist[15:8]), 0-255 的单调距离指示。
//------------------------------------------------------------------------------
module voice_dbg_rpt #(
    parameter BAUD_TICKS = 434,
    parameter PERIOD_MS  = 200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,
    input  wire       vad,        // 电平: VAD 判决
    input  wire       mfcc,       // 脉冲: 任一 MFCC 特征帧输出
    input  wire       owner,      // 电平: utter_vote 多数决 owner_valid
    input  wire       fr_match,   // 脉冲: 任一单帧 speaker match
    input  wire [1:0] cmd_id,     // cmd_vote 多数决命令
    input  wire [2:0] action,     // decision_fsm 动作 0停/2前/3左/4右
    input  wire [7:0] score,      // speaker 距离高位摘要
    output wire       tx
);
    wire busy; reg send; reg [7:0] bo;
    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send), .tx_data(bo), .tx(tx), .busy(busy));

    reg [9:0] ms; reg hb;
    always @(posedge clk) begin
        if (!rst_n) begin ms<=0; hb<=0; end
        else begin
            hb<=1'b0;
            if (tick_1ms) begin
                if (ms == PERIOD_MS[9:0]-1) begin ms<=0; hb<=1'b1; end
                else ms<=ms+1'b1;
            end
        end
    end

    // 脉冲锁存: 自上次上报以来出现过任一特征帧/任一单帧匹配
    reg mfcc_any, fr_any;
    always @(posedge clk) begin
        if (!rst_n) begin mfcc_any<=0; fr_any<=0; end
        else begin
            if (mfcc)     mfcc_any <= 1'b1;
            if (fr_match) fr_any   <= 1'b1;
            if (hb) begin mfcc_any <= 1'b0; fr_any <= 1'b0; end
        end
    end

    reg [2:0] bi; reg framing, sent;
    reg [7:0] b_v, b_m, b_o, b_c, b_a, b_s;
    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin framing<=0; sent<=0; bi<=0; b_v<=0; b_m<=0; b_o<=0; b_c<=0; b_a<=0; b_s<=0; end
        else begin
            if (!framing) begin
                sent<=0;
                if (hb) begin
                    b_v<={7'b0,vad}; b_m<={7'b0,mfcc_any}; b_o<={6'b0,fr_any,owner};
                    b_c<={6'b0,cmd_id}; b_a<={5'b0,action}; b_s<=score;
                    framing<=1; bi<=0;
                end
            end else if (!sent) begin
                if (!busy) begin
                    case (bi)
                        0: bo<=8'hAB;
                        1: bo<=b_v;
                        2: bo<=b_m;
                        3: bo<=b_o;
                        4: bo<=b_c;
                        5: bo<=b_a;
                        6: bo<=b_s;
                        default: bo<=8'hAB ^ b_v ^ b_m ^ b_o ^ b_c ^ b_a ^ b_s;
                    endcase
                    send<=1; sent<=1;
                end
            end else begin
                if (!busy) begin
                    sent<=0;
                    if (bi==7) framing<=0; else bi<=bi+1;
                end
            end
        end
    end
endmodule
