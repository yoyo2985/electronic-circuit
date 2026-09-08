//------------------------------------------------------------------------------
// feature_engine.v   B4 帧级统一特征引擎
//   一帧(N=64)单声道 24bit PCM → 13 维 MFCC。
//   复用已 PASS 的积木：front_chain(pre_emph+front_wind) / fft_core / logmel_chain /
//   dct2_mfcc；新增 Power 级 (re^2+im^2)>>PS。
//   默认 L 声道(输入已是选定单声道流)；R 声道由上层单独保留给方向。
//   enable=1 才处理(VAD 门控，可用 bypass=1 常开测试)。
//   流程：
//     WAIT --frame_start--> CAPT(收64采样并送front_chain) --> WINOUT(收64窗值)
//     --> FFTLOAD(按位倒序喂fft) --> FFT/POWER(k0..32) --> MELFEED(33 pow到logmel)
//     --> LOGOUT(收20 logmel) --> DCTLOAD(喂dct) --> DCTOUT(13 coeff) --> DONE
//   feature_valid+feature_index[0..12]+feature_data(int16 定标)。frame_done 一帧完成。
//------------------------------------------------------------------------------
module feature_engine #(
    parameter AW    = 24,
    parameter N     = 64,
    parameter NB    = 33,     // N/2+1
    parameter M     = 20,     // mel
    parameter K     = 13,     // MFCC 维
    parameter PS    = 22,     // power 定标 (re^2+im^2)>>PS
    parameter COEF_Q= 0       // 通常 0：dct 输出已 >>12 且量级适配 int16；>0 进一步定标
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,        // 1=处理（VAD 门控/bypass）
    input  wire              frame_start,   // 本帧开始
    input  wire              pcm_valid,
    input  wire signed [AW-1:0] pcm_data,
    output reg               busy,
    output reg               feature_valid,
    output reg  [3:0]        feature_index,
    output reg  signed [15:0] feature_data,
    output reg               frame_done
);
    localparam LOGN  = $clog2(N);          // 6
    localparam LOGN33= $clog2(NB + 1);     // 6
    localparam LOGM  = $clog2(M + 1);      // 5
    localparam LOGK  = $clog2(K + 1);      // 4

    localparam [3:0] S_WAIT=0, S_CAPT=1, S_WIN=2, S_FFTL=3, S_FFTP=4,
                     S_MELF=5, S_LOG=6, S_DCTL=7, S_DCT=8, S_DONE=9;

    // 握手信号（先声明，避免隐式网表）
    reg pcm_feed;
    reg signed [AW-1:0] pcm_feed_data;
    reg fft_in_ok;
    reg signed [AW-1:0] fft_in_re;
    reg lm_in_ok;
    reg [31:0] lm_in_pow;
    reg dct_in_ok;
    reg [15:0] dct_in_x;

    // ---------------- 积木例化 ----------------
    wire fc_ok, fc_first;
    wire signed [AW-1:0] fc_data;
    front_chain #(.AW(AW), .N(N)) u_fc (
        .clk(clk), .rst_n(rst_n),
        .sample_ok(pcm_feed), .sample(pcm_feed_data),
        .frame_valid(fc_ok), .frame_first(fc_first), .frame_data(fc_data)
    );

    wire fft_out_ok;
    wire signed [31:0] fft_re, fft_im;
    fft_core #(.AW(AW), .N(N)) u_fft (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fft_in_ok), .in_re(fft_in_re),
        .out_valid(fft_out_ok), .out_re(fft_re), .out_im(fft_im)
    );

    wire lm_ok;
    wire [15:0] lm_data;
    logmel_chain #(.NB(NB), .M(M), .CFQ(12), .XW(48), .FW(8), .BW(6)) u_lm (
        .clk(clk), .rst_n(rst_n),
        .in_valid(lm_in_ok), .in_pow(lm_in_pow),
        .out_valid(lm_ok), .out_logmel(lm_data)
    );

    wire dct_ok;
    wire [31:0] dct_c;
    dct2_mfcc #(.M(M), .K(K), .DQ(12)) u_dct (
        .clk(clk), .rst_n(rst_n),
        .in_valid(dct_in_ok), .in_x(dct_in_x),
        .out_valid(dct_ok), .out_c(dct_c)
    );

    // ---------------- 内部 RAM ----------------
    reg signed [AW-1:0] win[0:N-1];        // 窗值(自然序)
    reg [31:0] powr[0:NB-1];               // power bin
    reg [15:0] lm20[0:M-1];                // log-mel

    // ---------------- 位倒序 ----------------
    function [LOGN-1:0] brev(input [LOGN-1:0] v);
        integer q;
        begin
            brev = {LOGN{1'b0}};
            for (q = 0; q < LOGN; q = q + 1)
                brev[q] = v[LOGN-1-q];
        end
    endfunction

    reg [3:0]  st;
    reg [LOGN-1:0]   c64;
    reg [LOGN33-1:0] c33;
    reg [LOGM-1:0]   c20;
    reg [LOGN-1:0]   cw;        // win 写/读计数
    reg [5:0]  pc;              // fft 输出已收脉冲计数(0..32)
    reg signed [95:0] pacc;     // power 临时

    wire signed [63:0] sre = fft_re;
    wire signed [63:0] sim = fft_im;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            st <= S_WAIT; busy<=0; feature_valid<=0; frame_done<=0;
            feature_index<=4'd0; feature_data<=16'sd0;
            c64<=0; c33<=0; c20<=0; cw<=0; pc<=0;
            pcm_feed<=0; pcm_feed_data<=0;
            fft_in_ok<=0; fft_in_re<=0; lm_in_ok<=0; lm_in_pow<=0;
            dct_in_ok<=0; dct_in_x<=0; pacc<=0;
        end else begin
            feature_valid <= 1'b0;
            frame_done    <= 1'b0;
            pcm_feed      <= 1'b0;
            fft_in_ok     <= 1'b0;
            lm_in_ok      <= 1'b0;
            dct_in_ok     <= 1'b0;

            case (st)
                S_WAIT: begin
                    busy <= 1'b0;
                    if (enable && frame_start) begin
                        busy<=1'b1;
                        c64<=0; c33<=0; c20<=0; cw<=0; pc<=0;
                        st <= S_CAPT;
                    end
                end
                S_CAPT: begin
                    // 收 64 采样并连续送 front_chain（内部含预加重+加窗）
                    if (pcm_valid) begin
                        pcm_feed      <= 1'b1;
                        pcm_feed_data <= pcm_data;
                        if (c64 == N[LOGN-1:0]-1'b1) begin
                            c64<=0;
                            cw<=0;
                            st <= S_WIN;
                        end else c64 <= c64 + 1'b1;
                    end
                end
                S_WIN: begin
                    // 抓 front_chain 输出的 64 个窗值
                    if (fc_ok) begin
                        win[cw] <= fc_data;
                        if (cw == N[LOGN-1:0]-1'b1) begin
                            cw<=0;
                            c64<=0;
                            st <= S_FFTL;
                        end else cw <= cw + 1'b1;
                    end
                end
                S_FFTL: begin
                    // 按位倒序喂 FFT
                    fft_in_ok <= 1'b1;
                    fft_in_re <= win[brev(c64[LOGN-1:0])];
                    if (c64 == N[LOGN-1:0]-1'b1) begin
                        c64<=0; pc<=0;
                        st <= S_FFTP;
                    end else c64 <= c64 + 1'b1;
                end
                S_FFTP: begin
                    // FFT 自动跑完后输出 64 点；收前 33 点算 power
                    if (fft_out_ok && (pc < NB[5:0])) begin
                        pacc  = sre*sre + sim*sim;
                        powr[pc] <= (pacc >>> PS);
                        if (pc == NB[5:0] - 1'b1) begin
                            pc<=0; c33<=0;
                            st <= S_MELF;
                        end else pc <= pc + 1'b1;
                    end
                end
                S_MELF: begin
                    // 送 33 个 power 到 logmel_chain
                    lm_in_ok  <= 1'b1;
                    lm_in_pow <= powr[c33[LOGN33-1:0]];
                    if (c33 == NB[LOGN33-1:0]-1'b1) begin
                        c33<=0; c20<=0;
                        st <= S_LOG;
                    end else c33 <= c33 + 1'b1;
                end
                S_LOG: begin
                    // 收 20 个 log-mel
                    if (lm_ok) begin
                        lm20[c20] <= lm_data;
                        if (c20 == M[LOGM-1:0]-1'b1) begin
                            c20<=0;
                            st <= S_DCTL;
                        end else c20 <= c20 + 1'b1;
                    end
                end
                S_DCTL: begin
                    dct_in_ok <= 1'b1;
                    dct_in_x  <= lm20[c20[LOGM-1:0]];
                    if (c20 == M[LOGM-1:0]-1'b1) begin
                        c20<=0;
                        st <= S_DCT;
                    end else c20 <= c20 + 1'b1;
                end
                S_DCT: begin
                    // 收 13 个 MFCC 系数并定标输出
                    if (dct_ok) begin
                        feature_index <= c20[3:0];
                        feature_data  <= ($signed(dct_c) >>> COEF_Q);
                        feature_valid <= 1'b1;
                        if (c20 == K[LOGK-1:0]-1'b1) begin
                            c20<=0;
                            st <= S_DONE;
                        end else c20 <= c20 + 1'b1;
                    end
                end
                S_DONE: begin
                    busy      <= 1'b0;
                    frame_done<= 1'b1;
                    st        <= S_WAIT;
                end
                default: st <= S_WAIT;
            endcase
        end
    end
endmodule
