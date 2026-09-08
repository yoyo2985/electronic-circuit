//------------------------------------------------------------------------------
// pre_emph.v   B3-1 定点流式预加重（高通）：y[n] = x[n] - a*x[n-1]
//   定点：a ≈ A_FIX/2^Q（Q14, a≈0.97 → A_FIX=15892）。
//   实现：term = round(a*xprev) = (xprev*A_FIX + 2^(Q-1)) >>> Q（向下取整，
//         与 Python 对负数 >> 的 floor 一致 → 可逐点 Golden 比对）
//         y = x - term，饱和到 AW 位有符号。
//   接口：in_valid 每采样 1 拍（48k），out_valid 下一拍给结果（流水一拍）。
// 复位：同步低有效 rst_n。文件 py/gen_preemph_vec.py 生成比对向量。
//------------------------------------------------------------------------------
module pre_emph #(
    parameter AW    = 24,
    parameter Q     = 14,
    parameter A_FIX = 15892
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire signed [AW-1:0] x,
    output reg              out_valid,
    output reg  signed [AW-1:0] y
);
    localparam signed [47:0] AF = A_FIX;
    localparam signed [47:0] MAX = (1 << (AW - 1)) - 1;
    localparam signed [47:0] MIN = -(1 << (AW - 1));
    localparam signed [47:0] HALF_S = (1 << (Q - 1));   // 2^(Q-1)

    reg signed [AW-1:0] xprev;          // x[n-1]
    reg signed [47:0] m, term, s;       // 中间量（单写者，临时）

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            xprev     <= {AW{1'b0}};
            out_valid <= 1'b0;
            y         <= {AW{1'b0}};
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                m    = $signed(xprev) * AF;
                term = (m + HALF_S) >>> Q;
                s    = $signed(x) - term;
                if (s > MAX)      y <= MAX[AW-1:0];
                else if (s < MIN) y <= MIN[AW-1:0];
                else              y <= s[AW-1:0];
                out_valid <= 1'b1;
                xprev <= x;
            end
        end
    end

endmodule
