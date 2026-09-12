//------------------------------------------------------------------------------
// seg_decide.v  段级(段均值)决策 —— 替代逐帧 speaker_verify+utter_vote / cmd_matcher+cmd_vote
//
//   背景(2026-09-10 板上实测): 逐帧 L1 判定的 owner/stranger 分布完全重叠
//   (owner 帧 3584~6912 vs stranger 3584~7424), 且 cmd_matcher 每帧都出结果(含静音帧),
//   静音帧 argmin 恒选幅度最小的 stop 模板 + cmd_vote 平局取小 id ⇒ 命令恒为 stop。
//   而同一批模板在【段均值】层面可分: owner 段均值距 owner 模板 265~4106, 陌生人 4486~9134。
//
//   本模块复用 voice_cap_rpt 的段内累加(仅 vad 期间的帧), 段末以"不除法"等价式判决:
//       L1(mean, T) = (1/cnt)·Σ_d |sum[d] − cnt·T[d]|
//     owner: Σ_d|sum[d] − cnt·TPL_V[d]|  <  cnt·TH_OWN
//     cmd  : argmin_t Σ_d|sum[d] − cnt·TPL_t[d]|      (0停/1左/2右/3前, 符号同 decision_fsm)
//   输出 owner_valid / cmd_valid 为段末(vad_fall 后)单拍脉冲。
//
//   模板为参数常量内嵌(TD 不支持 $readmemh ROM), 来源 data/speaker/owner_template.mem,
//   data/commands/cmd_{stop,left,right,forward}.mem。TH_OWN=4300 取在
//   属主全词最大 4106(前进) 与 陌生人最小 4486 之间(数据见 reports/)。
//------------------------------------------------------------------------------
module seg_decide #(
    parameter N_DIM  = 13,
    parameter TH_OWN = 4300,        // 段均值 L1(→owner模板) 阈值
    parameter [207:0] TPL_V = 208'h001c005100f900f2008c004affbcff66fd0afc850179fb500bc9, // owner
    parameter [207:0] TPL_0 = 208'h00520020008300ae009fffd8fefeff93fe4efe870375f9b40868, // 0 stop (cap3 4段)
    parameter [207:0] TPL_1 = 208'h004e008700a3006300840078ffcfffddfd71fc6201fffb410a8b, // 1 left
    parameter [207:0] TPL_2 = 208'h004300b900dd00800099009cffd0ff74fcf8fbea018dfbe60b78, // 2 right
    parameter [207:0] TPL_3 = 208'h002cfff40094010300d8fffeff17ff31fdacfe430397fa0e08c1  // 3 forward (cap3 5段)
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       fe_valid,
    input  wire [3:0] fe_index,
    input  wire signed [15:0] fe_data,
    input  wire       vad,
    input  wire       vad_rise,
    input  wire       vad_fall,
    output reg        owner_valid,   // 段内锁存电平(段末置位, 下段 vad_rise 清): 段均值过 owner 闸
    output reg        seg_done,      // 段末单拍脉冲
    output reg  [1:0] cmd_id,        // 段末锁存 0停/1左/2右/3前
    output reg  [15:0] own_mean      // 调试: 段均值 L1(→owner模板)(精确, 32位恢复除法)
);
    integer k;
    reg signed [31:0] sum   [0:N_DIM-1];
    reg [31:0]        cnt;
    reg signed [31:0] sum_s [0:N_DIM-1];
    reg [31:0]        cnt_s;

    // ---- 段内累加(与 voice_cap_rpt 同口径) ----
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 32'd0;
            for (k = 0; k < N_DIM; k = k + 1) sum[k] <= 32'sd0;
        end else begin
            if (vad_rise) begin
                cnt <= 32'd0;
                for (k = 0; k < N_DIM; k = k + 1) sum[k] <= 32'sd0;
            end
            if (fe_valid && vad) begin
                if (fe_index == 4'd0) cnt <= cnt + 32'd1;
                sum[fe_index[3:0]] <= sum[fe_index[3:0]] + fe_data;
            end
        end
    end

    // ---- 段末判决 FSM ----
    localparam S_ACC=3'd0, S_LAT=3'd1, S_CALC=3'd2, S_DIV0=3'd3, S_DIV=3'd4, S_FIN=3'd5;
    reg [2:0]  st;
    reg [3:0]  d;
    reg signed [47:0] acc_v, acc0, acc1, acc2, acc3;
    reg signed [47:0] acc_v_c;
    reg signed [15:0] tv, t0, t1, t2, t3;
    reg signed [47:0] pv, p0, p1, p2, p3;
    reg signed [47:0] dv, d0, d1, d2, d3;
    reg signed [47:0] av, a0, a1, a2, a3;
    reg signed [47:0] best, thr;
    reg [1:0]  bestid;
    // 除法器
    reg [5:0]  di;
    reg [47:0] rmd, sh;
    reg [31:0] qot;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_ACC; owner_valid <= 1'b0; seg_done <= 1'b0; cmd_id <= 2'd0;
            acc_v<=0; acc0<=0; acc1<=0; acc2<=0; acc3<=0; d<=0; di<=0;
            rmd<=0; sh<=0; qot<=0; own_mean<=16'd0;
        end else begin
            seg_done <= 1'b0;
            case (st)
              S_ACC: begin
                        if (vad_rise) owner_valid <= 1'b0;   // 新段清 owner 电平
                        if (vad_fall) begin
                            cnt_s <= cnt;
                            for (k = 0; k < N_DIM; k = k + 1) sum_s[k] <= sum[k];
                            st <= S_LAT;
                        end
                     end
              S_LAT: begin
                        acc_v<=0; acc0<=0; acc1<=0; acc2<=0; acc3<=0; d<=0;
                        st <= S_CALC;
                     end
              S_CALC: begin
                        // 第 d 维: |sum − cnt*T|
                        tv = $signed(TPL_V[d*16 +: 16]);
                        t0 = $signed(TPL_0[d*16 +: 16]);
                        t1 = $signed(TPL_1[d*16 +: 16]);
                        t2 = $signed(TPL_2[d*16 +: 16]);
                        t3 = $signed(TPL_3[d*16 +: 16]);
                        pv = $signed({32'd0, cnt_s[15:0]}) * $signed({{32{tv[15]}}, tv});
                        p0 = $signed({32'd0, cnt_s[15:0]}) * $signed({{32{t0[15]}}, t0});
                        p1 = $signed({32'd0, cnt_s[15:0]}) * $signed({{32{t1[15]}}, t1});
                        p2 = $signed({32'd0, cnt_s[15:0]}) * $signed({{32{t2[15]}}, t2});
                        p3 = $signed({32'd0, cnt_s[15:0]}) * $signed({{32{t3[15]}}, t3});
                        dv = $signed(sum_s[d]) - pv;
                        d0 = $signed(sum_s[d]) - p0;
                        d1 = $signed(sum_s[d]) - p1;
                        d2 = $signed(sum_s[d]) - p2;
                        d3 = $signed(sum_s[d]) - p3;
                        av = (dv < 0) ? -dv : dv;
                        a0 = (d0 < 0) ? -d0 : d0;
                        a1 = (d1 < 0) ? -d1 : d1;
                        a2 = (d2 < 0) ? -d2 : d2;
                        a3 = (d3 < 0) ? -d3 : d3;
                        acc_v <= acc_v + av;
                        acc0  <= acc0  + a0;
                        acc1  <= acc1  + a1;
                        acc2  <= acc2  + a2;
                        acc3  <= acc3  + a3;
                        if (d == N_DIM-1) begin st <= S_DIV0; acc_v_c <= acc_v + av; end
                        else d <= d + 1'b1;
                     end
              S_DIV0: begin
                        rmd <= 48'd0; qot <= 32'd0; di <= 6'd32;
                        st <= S_DIV;
                      end
              S_DIV: begin
                        sh = (rmd << 1) | {47'b0, acc_v_c[di-1]};
                        if (sh >= {32'd0, cnt_s[15:0]}) begin
                            rmd <= sh - {32'd0, cnt_s[15:0]};
                            qot <= (qot << 1) | 32'd1;
                        end else begin
                            rmd <= sh;
                            qot <= (qot << 1);
                        end
                        if (di == 6'd1) st <= S_FIN; else di <= di - 1'b1;
                      end
              S_FIN: begin
                        thr = $signed({32'd0, cnt_s[15:0]}) * TH_OWN;
                        owner_valid <= (cnt_s != 0) && (acc_v < thr);
                        best = acc0; bestid = 2'd0;
                        if (acc1 < best) begin best = acc1; bestid = 2'd1; end
                        if (acc2 < best) begin best = acc2; bestid = 2'd2; end
                        if (acc3 < best) begin best = acc3; bestid = 2'd3; end
                        cmd_id    <= bestid;
                        seg_done  <= (cnt_s != 0);
                        own_mean  <= qot[15:0];
                        st <= S_ACC;
                      end
              default: st <= S_ACC;
            endcase
        end
    end
endmodule
