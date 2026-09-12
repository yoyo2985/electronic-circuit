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
  function [15:0] win_fn(input integer a);
    begin
      case (a)
          0: win_fn = 16'h0000;
          1: win_fn = 16'h004f;
          2: win_fn = 16'h013b;
          3: win_fn = 16'h02c1;
          4: win_fn = 16'h04df;
          5: win_fn = 16'h078f;
          6: win_fn = 16'h0ac9;
          7: win_fn = 16'h0e87;
          8: win_fn = 16'h12bf;
          9: win_fn = 16'h1766;
          10: win_fn = 16'h1c72;
          11: win_fn = 16'h21d5;
          12: win_fn = 16'h2782;
          13: win_fn = 16'h2d6c;
          14: win_fn = 16'h3384;
          15: win_fn = 16'h39ba;
          16: win_fn = 16'h4000;
          17: win_fn = 16'h4646;
          18: win_fn = 16'h4c7c;
          19: win_fn = 16'h5294;
          20: win_fn = 16'h587e;
          21: win_fn = 16'h5e2b;
          22: win_fn = 16'h638e;
          23: win_fn = 16'h689a;
          24: win_fn = 16'h6d41;
          25: win_fn = 16'h7179;
          26: win_fn = 16'h7537;
          27: win_fn = 16'h7871;
          28: win_fn = 16'h7b21;
          29: win_fn = 16'h7d3f;
          30: win_fn = 16'h7ec5;
          31: win_fn = 16'h7fb1;
          32: win_fn = 16'h8000;
          33: win_fn = 16'h7fb1;
          34: win_fn = 16'h7ec5;
          35: win_fn = 16'h7d3f;
          36: win_fn = 16'h7b21;
          37: win_fn = 16'h7871;
          38: win_fn = 16'h7537;
          39: win_fn = 16'h7179;
          40: win_fn = 16'h6d41;
          41: win_fn = 16'h689a;
          42: win_fn = 16'h638e;
          43: win_fn = 16'h5e2b;
          44: win_fn = 16'h587e;
          45: win_fn = 16'h5294;
          46: win_fn = 16'h4c7c;
          47: win_fn = 16'h4646;
          48: win_fn = 16'h4000;
          49: win_fn = 16'h39ba;
          50: win_fn = 16'h3384;
          51: win_fn = 16'h2d6c;
          52: win_fn = 16'h2782;
          53: win_fn = 16'h21d5;
          54: win_fn = 16'h1c72;
          55: win_fn = 16'h1766;
          56: win_fn = 16'h12bf;
          57: win_fn = 16'h0e87;
          58: win_fn = 16'h0ac9;
          59: win_fn = 16'h078f;
          60: win_fn = 16'h04df;
          61: win_fn = 16'h02c1;
          62: win_fn = 16'h013b;
          63: win_fn = 16'h004f;
        default: win_fn = 16'sh0000;
      endcase
    end
  endfunction


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
                pw = $signed(wbuf[ridx]) * $signed({1'b0, win_fn(ridx)});
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
