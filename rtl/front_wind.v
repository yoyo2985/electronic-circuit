//------------------------------------------------------------------------------
// front_wind.v   B3-2 分帧 + Q15 Hann 加窗（单缓冲，帧间无重叠 hop=N）
//   输入连续 PCM（可已预加重；pre_emph 上游链），sample_ok 每采样 1 拍(48k)。
//   收满 N 个 → 紧接着 N 拍逐点输出 加窗帧：
//       out = round(wbuf[i]*win[i]/2^15)，饱和 AW 位有符号。
//   out_first 在每帧第 0 个字给 1 拍（帧起始标志）。
//   说明：帧读出只需 N 个 sys 周期(≈1.3us@N64)，远小于 48k 采样间隔(≈20.8us)，
//         因此帧边界后下一个采样到来前读帧早已完成，无丢点、无需双缓冲。
//   窗系数：data/hann_64.mem（python py/gen_wind_vec.py 生成，16bit 无符号 hex）。
//   定点：与 python 参考一致 (sample*win + 2^14)>>15 后饱和。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module front_wind #(
    parameter AW = 24,
    parameter N  = 64
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_ok,     // 每输入采样 1 拍
    input  wire signed [AW-1:0] sample,
    output reg              out_valid,     // 加窗输出有效（每帧连续 N 拍）
    output reg              out_first,     // 帧起始字
    output reg  signed [AW-1:0] out_data
);
    localparam LOGN = $clog2(N);
    localparam [LOGN-1:0] NM1 = N - 1;           // 帧内最大索引
    localparam signed [47:0] HALF = (1 << 14);   // 2^14 舍入
    localparam signed [47:0] MAX = (1 << (AW - 1)) - 1;
    localparam signed [47:0] MIN = -(1 << (AW - 1));

    reg signed [AW-1:0] wbuf[0:N-1];
    reg [15:0]          win[0:N-1];
    initial $readmemh("data/hann_64.mem", win);

    reg [LOGN-1:0] wcnt;              // 写入计数
    reg            emit;              // 正在读帧输出
    reg [LOGN-1:0] ridx;              // 读出索引
    reg signed [47:0] pw, o;          // 中间量（单写者）

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            wcnt      <= {LOGN{1'b0}};
            emit      <= 1'b0;
            ridx      <= {LOGN{1'b0}};
            out_valid <= 1'b0;
            out_first <= 1'b0;
            out_data  <= {AW{1'b0}};
        end else begin
            out_valid <= 1'b0;
            out_first <= 1'b0;
            if (sample_ok && !emit) begin
                wbuf[wcnt] <= sample;
                if (wcnt == NM1) begin
                    wcnt <= {LOGN{1'b0}};
                    emit <= 1'b1;          // 满帧，下一拍开始输出
                    ridx <= {LOGN{1'b0}};
                end else begin
                    wcnt <= wcnt + 1'b1;
                end
            end
            // （真实 48k 间隔远大于 N 拍读出，emit 期间不会来新采样；来了则丢弃）

            if (emit) begin
                pw = $signed(wbuf[ridx]) * $signed({1'b0, win[ridx]});
                o  = (pw + HALF) >>> 15;   // Q15，向下取整
                if (o > MAX)      out_data <= MAX[AW-1:0];
                else if (o < MIN) out_data <= MIN[AW-1:0];
                else              out_data <= o[AW-1:0];
                out_valid <= 1'b1;
                if (ridx == {LOGN{1'b0}}) out_first <= 1'b1;
                if (ridx == NM1) begin
                    emit <= 1'b0;
                    ridx <= {LOGN{1'b0}};
                end else begin
                    ridx <= ridx + 1'b1;
                end
            end
        end
    end

endmodule
