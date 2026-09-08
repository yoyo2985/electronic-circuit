//------------------------------------------------------------------------------
// mel_bank.v   B3-4a Mel 滤波器组能量累加
//   载入 NB 个功率 bin(power=re^2+im^2 或其缩放，自然频序)，
//   对 M 个 Mel 三角窗分别做 mel[m] = Σ_k pow[k]*coef[m][k] >> CFQ（floor）。
//   系数表 data/mel_coef.mem（M*NB，QCF 量化，hex4），由 py/gen_mel_vec.py 生成。
//   输出：M 个 mel 能量字，逐一拍 out_valid。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module mel_bank #(
    parameter NB  = 9,
    parameter M   = 6,
    parameter CFQ = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,        // 载入功率 bin（每 bin 一拍，NB 个）
    input  wire [31:0]      in_pow,
    output reg              out_valid,       // mel 能量输出有效（M 拍）
    output reg  [63:0]      out_mel
);
    localparam LOGM = $clog2(M + 1);
    localparam LOGN = $clog2(NB + 1);
    localparam [LOGN-1:0] NBM1 = NB - 1;
    localparam [LOGM-1:0] MM1  = M - 1;

    reg [31:0] pow[0:NB-1];
    reg [15:0] coef[0:M*NB-1];
    initial $readmemh("data/mel_coef.mem", coef);

    localparam [1:0] S_LOAD = 0, S_CALC = 1;
    reg [1:0]  st;
    reg [LOGN-1:0] cnt;
    reg [LOGM-1:0] m;
    reg [LOGN-1:0] k;
    reg [63:0] acc;
    reg [63:0] prod;
    reg [63:0] accn;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            st        <= S_LOAD;
            cnt       <= {LOGN{1'b0}};
            m         <= {LOGM{1'b0}};
            k         <= {LOGN{1'b0}};
            acc       <= 64'd0;
            accn      <= 64'd0;
            prod      <= 64'd0;
            out_valid <= 1'b0;
            out_mel   <= 64'd0;
        end else begin
            out_valid <= 1'b0;
            case (st)
                S_LOAD: begin
                    if (in_valid) begin
                        pow[cnt] <= in_pow;
                        if (cnt == NBM1) begin
                            cnt <= {LOGN{1'b0}};
                            m   <= {LOGM{1'b0}};
                            k   <= {LOGN{1'b0}};
                            acc <= 64'd0;
                            st  <= S_CALC;
                        end else cnt <= cnt + 1'b1;
                    end
                end
                S_CALC: begin
                    prod = pow[k] * coef[m*NB + k];
                    accn = acc + prod;
                    if (k == NBM1) begin
                        out_mel   <= accn >> CFQ;
                        out_valid <= 1'b1;
                        if (m == MM1) begin
                            st <= S_LOAD;       // 一帧完成，可载入下一帧
                        end
                        m   <= (m == MM1) ? {LOGM{1'b0}} : m + 1'b1;
                        acc <= 64'd0;
                        k   <= {LOGN{1'b0}};
                    end else begin
                        acc <= accn;
                        k   <= k + 1'b1;
                    end
                end
                default: st <= S_LOAD;
            endcase
        end
    end
endmodule
