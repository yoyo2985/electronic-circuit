//------------------------------------------------------------------------------
// keypad_scan.v   4x4 矩阵键盘扫描（单时钟域 + tick 轮询）
//   行驱动：row_out 低有效逐行轮询 1110→1101→1011→0111→1110…，每 1ms 换一行。
//   列读回：col_in 低=按下（板上列线已有上拉，无键=全 1）。
//   每 4ms 完成一次整矩阵快照(16 位)，对快照做向量级消抖：
//     需连续 DEBOUNCE_N 次快照取值一致才认为稳定，消除机械抖动。
//   输出：key_idx = row*4+col (0..15)；新键稳定后 key_event 产生 1 拍脉冲。
//   键号 0..15 为“行优先索引”，与丝印编号的对应关系按板卡布局另行映射。
// 参数化：DEBOUNCE_N 稳定快照次数（仿真改小，如 2）。
// 复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module keypad_scan #(
    parameter DEBOUNCE_N = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_1ms,     // 1ms 节拍
    input  wire [3:0]  col_in,       // 读回列，低=按下
    output reg  [3:0]  row_out,      // 驱动行，低有效，逐行轮询
    output reg         key_event,    // 新键消抖确认事件（1 拍）
    output reg  [3:0]  key_idx       // 最后确认键号 0..15 = row*4+col
);
    // ---- 行轮询计数 0..3，row_out = 相应行拉低 ----
    reg [1:0] rcnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            rcnt    <= 2'd0;
            row_out <= 4'b1110;               // 先扫行0
        end else if (tick_1ms) begin
            rcnt    <= rcnt + 2'd1;
            row_out <= {row_out[2:0], row_out[3]};   // 循环移位
        end
    end

    // ---- 列同步（两级 FF）；内部统一为 1=按下，故取反 ----
    reg [3:0] col1, col2;
    wire [3:0] colp = ~col2;   // 按下位：col_in 低=按下 => 取反后高=按下
    always @(posedge clk) begin
        if (!rst_n) begin col1 <= 4'h0; col2 <= 4'hF; end
        else begin col1 <= col_in; col2 <= col1; end
    end

    // ---- 快照组装 / 向量消抖 / 事件检测（合并到一个 always，避免多驱动）----
    reg [15:0] snap;          // 本轮已采到的各行
    reg [15:0] stable_mat;    // 消抖后稳定矩阵
    reg [15:0] cand_mat;      // 待确认候选
    reg [15:0] stable_prev;   // 上一快照拍的稳定矩阵（慢一拍，用于找“新增按下”）
    reg [3:0]  dcnt;          // 消抖计数

    // 当前完整 16 位快照（每 nibble 一行，1=该键按下）
    wire [15:0] mat_now = {colp, snap[11:8], snap[7:4], snap[3:0]};

    // 新增按下位 = (稳定矩阵 且 上一拍没有)；用于事件检测
    wire [15:0] diff_bits = stable_mat & ~stable_prev;

    // 取 diff_bits 最低置 1 位 => 键号
    reg [3:0] low_one;
    integer m;
    reg foundl;
    always @(*) begin
        low_one = 4'd0; foundl = 1'b0;
        for (m = 0; m < 16; m = m + 1)
            if (diff_bits[m] && !foundl) begin
                low_one = m[3:0]; foundl = 1'b1;
            end
    end

    always @(posedge clk) begin
        key_event <= 1'b0;                        // 默认无事件
        if (!rst_n) begin
            snap        <= 16'h0000;
            stable_mat  <= 16'h0000;
            cand_mat    <= 16'h0000;
            stable_prev <= 16'h0000;
            dcnt        <= 4'd0;
            key_idx     <= 4'd0;
        end else if (tick_1ms) begin
            // 记录当前行(rcnt)的列状态进 snap 对应位置
            case (rcnt)
                2'd0:     snap[3:0] <= colp;
                2'd1:     snap[7:4] <= colp;
                2'd2:     snap[11:8] <= colp;
                default:  snap[15:12] <= colp;
            endcase

            // 每扫完第 3 行(rcnt==3)即得到完整 16 位快照，做消抖 + 事件
            if (rcnt == 2'd3) begin
                if (mat_now == stable_mat) begin
                    dcnt <= 4'd0;                       // 与稳定值一致
                end else if (mat_now == cand_mat) begin
                    dcnt <= dcnt + 4'd1;
                    if (dcnt == DEBOUNCE_N - 1)         // 连续 DEBOUNCE_N 次同值 → 接受
                        stable_mat <= mat_now;
                end else begin
                    cand_mat <= mat_now;
                    dcnt     <= 4'd1;
                end

                // 事件：stable_prev 比 stable_mat 慢一拍，diff 即“这次新出现”的按下
                if (diff_bits != 16'h0000) begin
                    key_event <= 1'b1;
                    key_idx   <= low_one;
                end
                stable_prev <= stable_mat;              // 记录本次稳定矩阵
            end
        end
    end
endmodule
