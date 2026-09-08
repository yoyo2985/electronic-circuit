//------------------------------------------------------------------------------
// fft_core.v   B3-3 radix-2 迭代定点 FFT（DIT）
//   N=2^L。输入 N 个实采样（已按位倒序排好，RTL 顺序载入即可），in_valid 逐点。
//   载满自动跑 L 级蝶形（每级 N/2 个、每个一拍），逐级把和差 >>1（≈输出 DFT/N）。
//   输出：自然频率序 k=0..N-1 逐点 out_re/out_im（各 32bit 有符号）。
//   旋转因子表 Q15：data/tw_re_16.mem、tw_im_16.mem（py/gen_fft_vec.py 生成）。
//   定点为容差比对：差异源于逐级 floor>>1 与 Q15 截断。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module fft_core #(
    parameter AW = 24,
    parameter N  = 16
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [AW-1:0] in_re,
    output reg                out_valid,
    output reg  signed [31:0] out_re,
    output reg  signed [31:0] out_im
);
    localparam LOG   = $clog2(N);
    localparam NB    = (N >> 1) * LOG;
    localparam LOGN  = $clog2(N + 1);
    localparam LOGNB = $clog2(NB + 1);

    reg signed [31:0] re[0:N-1];
    reg signed [31:0] im[0:N-1];
    reg signed [15:0] tw_re[0:N-1];
    reg signed [15:0] tw_im[0:N-1];
    initial $readmemh("data/tw_re_16.mem", tw_re);
    initial $readmemh("data/tw_im_16.mem", tw_im);

    localparam [1:0] S_LOAD = 0, S_RUN = 1, S_OUT = 2;
    reg [1:0]  st;
    reg [LOGN-1:0]  cnt;
    reg [LOGNB-1:0] bb;

    // ---- 当前蝶形参数（组合，来自 bb）----
    wire [LOG-1:0] stage_w = bb >> (LOG - 1);           // 0..L-1
    wire [LOG-2:0] qw      = bb[LOG-2:0];               // 段内蝶形 0..N/2-1
    wire [LOG-1:0] half    = 1 << stage_w;
    wire [LOG-1:0] g       = qw >> stage_w;
    wire [LOG-1:0] j       = qw & (half - 1);
    wire [LOG-1:0] kbase   = g << (stage_w + 1);
    wire [LOG-1:0] addr_a  = kbase + j;
    wire [LOG-1:0] addr_b  = addr_a + half;
    wire [LOG-1:0] t_idx   = j << (LOG - 1 - stage_w);

    reg signed [63:0] tr, ti, s1, s2;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            st        <= S_LOAD;
            cnt       <= {LOGN{1'b0}};
            bb        <= {LOGNB{1'b0}};
            out_valid <= 1'b0;
            out_re    <= 32'sd0;
            out_im    <= 32'sd0;
        end else begin
            out_valid <= 1'b0;
            case (st)
                S_LOAD: begin
                    if (in_valid) begin
                        re[cnt] <= {{(32-AW){in_re[AW-1]}}, in_re};
                        im[cnt] <= 32'sd0;
                        if (cnt == N[LOGN-1:0] - 1'b1) begin
                            cnt <= {LOGN{1'b0}};
                            bb  <= {LOGNB{1'b0}};
                            st  <= S_RUN;
                        end else cnt <= cnt + 1'b1;
                    end
                end
                S_RUN: begin
                    // t = w * Xb，w = e^{-i2π·t_idx/N}（Q15）
                    tr = ($signed(re[addr_b]) * $signed(tw_re[t_idx])
                        - $signed(im[addr_b]) * $signed(tw_im[t_idx])) >>> 15;
                    ti = ($signed(re[addr_b]) * $signed(tw_im[t_idx])
                        + $signed(im[addr_b]) * $signed(tw_re[t_idx])) >>> 15;
                    // Xa±t，逐级 >>1
                    s1 = ($signed(re[addr_a]) + tr) >>> 1;
                    s2 = ($signed(im[addr_a]) + ti) >>> 1;
                    re[addr_a] <= s1[31:0];
                    im[addr_a] <= s2[31:0];
                    s1 = ($signed(re[addr_a]) - tr) >>> 1;
                    s2 = ($signed(im[addr_a]) - ti) >>> 1;
                    re[addr_b] <= s1[31:0];
                    im[addr_b] <= s2[31:0];
                    if (bb == NB[LOGNB-1:0] - 1'b1) begin
                        bb  <= {LOGNB{1'b0}};
                        cnt <= {LOGN{1'b0}};
                        st  <= S_OUT;
                    end else bb <= bb + 1'b1;
                end
                S_OUT: begin
                    out_valid <= 1'b1;
                    out_re    <= re[cnt];
                    out_im    <= im[cnt];
                    if (cnt == N[LOGN-1:0] - 1'b1) begin
                        cnt <= {LOGN{1'b0}};
                        st  <= S_LOAD;
                    end else cnt <= cnt + 1'b1;
                end
                default: st <= S_LOAD;
            endcase
        end
    end
endmodule
