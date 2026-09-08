//------------------------------------------------------------------------------
// audio_energy.v   每声道短时能量（窗口平均 |x|）
//   在每个 sample_ok(=立体声对 48k) 上把左右采样的 |幅度| 累加，每 2^WIN_LOG2
//   个采样(≈21ms)出一个窗口平均，供 LED 条 / 数码管 / UART 显示。
//   音频是无符号远小于满幅的正弦，用平均绝对值即可分辨"哪只麦克风响"。
// 定点说明：|x| 先扩到 AW+1 位求绝对值防 -2^(AW-1) 溢出，再累加；
//   avg = sum >> WIN_LOG2 得 AW+1 位平均幅度。avg 低 8 位(>>8)送 UART 16bit。
// 复位：同步低有效 rst_n。pcm_l/pcm_r 来自 audio_pcm_bridge(sys 域, 帧间稳定)。
//------------------------------------------------------------------------------
module audio_energy #(
    parameter AW       = 24,          // PCM 位宽
    parameter WIN_LOG2 = 10           // 窗口 2^10 = 1024 帧 ≈ 21.3ms @48k
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_ok,     // 每立体声对 1 拍（audio_pcm_bridge.pair_valid）
    input  wire [AW-1:0]    pcm_l,
    input  wire [AW-1:0]    pcm_r,
    output reg  [AW:0]      avg_l,         // 左窗平均幅度 (AW+1 位)
    output reg  [AW:0]      avg_r,
    output reg              win_done       // 窗口结束 1 拍
);
    localparam WIN       = 1 << WIN_LOG2;
    localparam CNT_W     = WIN_LOG2;
    localparam SUM_W     = AW + WIN_LOG2 + 1;   // 1024×2^23 需 34 位，留 1 位
    localparam AVG_W     = AW + 1;              // avg 可到 2^(AW-1) → AW+1 位

    reg [CNT_W-1:0] cnt;
    reg [SUM_W-1:0] sum_l, sum_r;

    // 组合：AW 位有符号采样 → AW+1 位幅度
    wire signed [AW-1:0]  sl = pcm_l;
    wire signed [AW-1:0]  sr = pcm_r;
    wire signed [AW:0]    el = {sl[AW-1], sl};   // 符号扩展
    wire signed [AW:0]    er = {sr[AW-1], sr};
    wire [AW:0] mag_l = el[AW] ? (~el + 1'b1) : el[AW:0];
    wire [AW:0] mag_r = er[AW] ? (~er + 1'b1) : er[AW:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt      <= {CNT_W{1'b0}};
            sum_l    <= {SUM_W{1'b0}};
            sum_r    <= {SUM_W{1'b0}};
            avg_l    <= {AVG_W{1'b0}};
            avg_r    <= {AVG_W{1'b0}};
            win_done <= 1'b0;
        end else begin
            win_done <= 1'b0;
            if (sample_ok) begin
                sum_l <= sum_l + mag_l;
                sum_r <= sum_r + mag_r;
                if (cnt == WIN[CNT_W-1:0] - 1'b1) begin
                    // 本窗最后一个采样，先把当前点计入平均再清零
                    avg_l    <= ((sum_l + mag_l) >> WIN_LOG2);
                    avg_r    <= ((sum_r + mag_r) >> WIN_LOG2);
                    sum_l    <= {SUM_W{1'b0}};
                    sum_r    <= {SUM_W{1'b0}};
                    cnt      <= {CNT_W{1'b0}};
                    win_done <= 1'b1;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule
