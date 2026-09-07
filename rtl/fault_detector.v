//------------------------------------------------------------------------------
// fault_detector.v   运行故障检测：堵转(13)
//   在 run 期间且误差超过 ERR_TOL 时，若位置连续 STALL_MS 个 tick 不变化，
//   判定“堵转/负载卡死”，输出 faulted=1（锁存，直到 ack 或复位）。
//   到位(误差小)或位置在移动都视为正常并清计数。
// 参数化：STALL_MS / ERR_TOL。复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module fault_detector #(
    parameter STALL_MS = 200,
    parameter ERR_TOL  = 5
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_ctrl,
    input  wire       run,          // 1=运动中(来自 FSM)
    input  wire [9:0] pos,
    input  wire [9:0] target,
    input  wire       ack,          // 故障确认清除
    output reg        faulted       // 1=故障锁存
);
    localparam CW = $clog2(STALL_MS);
    reg [CW:0]   cnt;               // 留余量防止 STALL_MS=2^k
    reg [9:0]    pprev;

    always @(posedge clk) begin
        pprev <= pos;
        if (!rst_n) begin
            cnt     <= 0;
            faulted <= 1'b0;
        end else if (!run) begin
            cnt     <= 0;
            faulted <= 1'b0;         // 停动即清除（锁存交给 FSM）
        end else if (faulted) begin
            if (ack) faulted <= 1'b0;
        end else begin
            if (ack) faulted <= 1'b0;
            if ((target > pos ? (target - pos) : (pos - target)) <= ERR_TOL) begin
                cnt <= 0;                    // 已到位
            end else if (pos == pprev) begin
                if (cnt >= STALL_MS - 1) faulted <= 1'b1;
                else cnt <= cnt + 1;
            end else begin
                cnt <= 0;                    // 位置在变 → 正常
            end
        end
    end
endmodule
