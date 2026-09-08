//------------------------------------------------------------------------------
// dct2_mfcc.v   B3-5 正交 DCT-II（MFCC 取前 K 系数）
//   载入 M 个 log-mel，算 y[k]=Σ_m x[m]*b[k][m] >> DQ（floor）。
//   基矩阵 b[k][m]=c_k·cos(π/M(m+0.5)k)·2^DQ，data/dct_basis.mem(M*K,int16)。
//   输出 K 个 DCT 系数，逐一拍。与 py/gen_dct_vec.py 整数镜像一致。
//------------------------------------------------------------------------------
module dct2_mfcc #(
    parameter M  = 6,
    parameter K  = 4,
    parameter DQ = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,      // 载入 x[m]（M 拍）
    input  wire [15:0]      in_x,
    output reg              out_valid,     // 系数输出（K 拍）
    output reg  [31:0]      out_c
);
    localparam LOGM = $clog2(M + 1);
    localparam LOGK = $clog2(K + 1);
    localparam [LOGM-1:0] MM1 = M - 1;
    localparam [LOGK-1:0] KM1 = K - 1;

    reg signed [31:0] xbuf[0:M-1];
    reg signed [15:0] basis[0:M*K-1];
    initial $readmemh("data/dct_basis.mem", basis);

    localparam [1:0] S_LOAD = 0, S_CALC = 1;
    reg [1:0]  st;
    reg [LOGM-1:0] cnt;
    reg [LOGK-1:0] k;
    reg [LOGM-1:0] m;
    reg signed [63:0] acc;
    reg signed [63:0] accn;
    reg signed [63:0] prod;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            st        <= S_LOAD;
            cnt       <= {LOGM{1'b0}};
            k         <= {LOGK{1'b0}};
            m         <= {LOGM{1'b0}};
            acc       <= 64'sd0;
            accn      <= 64'sd0;
            prod      <= 64'sd0;
            out_valid <= 1'b0;
            out_c     <= 32'sd0;
        end else begin
            out_valid <= 1'b0;
            case (st)
                S_LOAD: begin
                    if (in_valid) begin
                        xbuf[cnt] <= $signed(in_x);
                        if (cnt == MM1) begin
                            cnt <= {LOGM{1'b0}};
                            k   <= {LOGK{1'b0}};
                            m   <= {LOGM{1'b0}};
                            acc <= 64'sd0;
                            st  <= S_CALC;
                        end else cnt <= cnt + 1'b1;
                    end
                end
                S_CALC: begin
                    prod = $signed(xbuf[m]) * $signed(basis[k*M + m]);
                    accn = acc + prod;
                    if (m == MM1) begin
                        out_c     <= (accn >>> DQ);
                        out_valid <= 1'b1;
                        acc       <= 64'sd0;
                        m         <= {LOGM{1'b0}};
                        if (k == KM1) begin
                            k  <= {LOGK{1'b0}};
                            st <= S_LOAD;          // 本帧完成
                        end else k <= k + 1'b1;
                    end else begin
                        acc <= accn;
                        m   <= m + 1'b1;
                    end
                end
                default: st <= S_LOAD;
            endcase
        end
    end
endmodule
