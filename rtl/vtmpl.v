//------------------------------------------------------------------------------
// vtmpl.v   C2-lite 声纹模板匹配：对 DIM 维向量算 L1 模板距离并阈值判定
//   载入 DIM 个测试特征(如 MFCC/平均向量)，dist=Σ|x[i]-t[i]|；dist<=TH→match。
//   模板 t[i] 存 data/vtmpl.mem。每 DIM 拍出一组结果。与 py 整数镜像一致。
//------------------------------------------------------------------------------
module vtmpl #(
    parameter DIM = 4,
    parameter TH  = 500,
    parameter TPL = "data/vtmpl.mem"
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,      // 载入特征（每维一拍，连续按 DIM 分组）
    input  wire signed [15:0] in_v,
    output reg              out_valid,     // 一组算完
    output reg  [31:0]      out_dist,
    output reg              out_match
);
    localparam LOGD = $clog2(DIM + 1);
    localparam [LOGD-1:0] DM1 = DIM - 1;

    reg signed [15:0] tpl[0:DIM-1];
    initial $readmemh(TPL, tpl);

    reg [LOGD-1:0] cnt;
    reg signed [39:0] acc;
    reg signed [39:0] d;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            cnt       <= {LOGD{1'b0}};
            acc       <= 40'sd0;
            d         <= 40'sd0;
            out_valid <= 1'b0;
            out_dist  <= 32'sd0;
            out_match <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                d = $signed(in_v) - $signed(tpl[cnt]);
                if (d < 0) d = -d;
                acc = acc + d;
                if (cnt == DM1) begin
                    out_dist  <= acc[31:0];
                    out_match <= (acc <= TH) ? 1'b1 : 1'b0;
                    out_valid <= 1'b1;
                    acc       <= 40'sd0;
                    cnt       <= {LOGD{1'b0}};
                end else cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
