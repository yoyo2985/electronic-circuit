// log2_lut.v  B3-4b 定点 log2 近似(位扫描+尾数 LUT)  — 系数以 case 逻辑内嵌(TD 可综合)
//   内容与 sim/audio_sim/data/log2_lut.mem 一致；TD 不支持 $readmemh/initial 初始化 ROM,
//   故改为组合 case-ROM(有驱动)。算法/数值不变。
module log2_lut #(parameter XW=48, FW=8, BW=6)(
  input wire clk, input wire rst_n,
  input wire in_valid, input wire [XW-1:0] in_x,
  output reg out_valid, output reg [15:0] out_l);
  localparam LOGW=$clog2(XW+1);
  localparam NW=XW+BW+8;

  function [15:0] lut_fn(input integer a);
    begin
      case (a)
          0: lut_fn = 16'h0000;
          1: lut_fn = 16'h0006;
          2: lut_fn = 16'h000b;
          3: lut_fn = 16'h0011;
          4: lut_fn = 16'h0016;
          5: lut_fn = 16'h001c;
          6: lut_fn = 16'h0021;
          7: lut_fn = 16'h0026;
          8: lut_fn = 16'h002c;
          9: lut_fn = 16'h0031;
          10: lut_fn = 16'h0036;
          11: lut_fn = 16'h003b;
          12: lut_fn = 16'h003f;
          13: lut_fn = 16'h0044;
          14: lut_fn = 16'h0049;
          15: lut_fn = 16'h004e;
          16: lut_fn = 16'h0052;
          17: lut_fn = 16'h0057;
          18: lut_fn = 16'h005c;
          19: lut_fn = 16'h0060;
          20: lut_fn = 16'h0064;
          21: lut_fn = 16'h0069;
          22: lut_fn = 16'h006d;
          23: lut_fn = 16'h0071;
          24: lut_fn = 16'h0076;
          25: lut_fn = 16'h007a;
          26: lut_fn = 16'h007e;
          27: lut_fn = 16'h0082;
          28: lut_fn = 16'h0086;
          29: lut_fn = 16'h008a;
          30: lut_fn = 16'h008e;
          31: lut_fn = 16'h0092;
          32: lut_fn = 16'h0096;
          33: lut_fn = 16'h009a;
          34: lut_fn = 16'h009d;
          35: lut_fn = 16'h00a1;
          36: lut_fn = 16'h00a5;
          37: lut_fn = 16'h00a9;
          38: lut_fn = 16'h00ac;
          39: lut_fn = 16'h00b0;
          40: lut_fn = 16'h00b3;
          41: lut_fn = 16'h00b7;
          42: lut_fn = 16'h00ba;
          43: lut_fn = 16'h00be;
          44: lut_fn = 16'h00c1;
          45: lut_fn = 16'h00c5;
          46: lut_fn = 16'h00c8;
          47: lut_fn = 16'h00cb;
          48: lut_fn = 16'h00cf;
          49: lut_fn = 16'h00d2;
          50: lut_fn = 16'h00d5;
          51: lut_fn = 16'h00d8;
          52: lut_fn = 16'h00dc;
          53: lut_fn = 16'h00df;
          54: lut_fn = 16'h00e2;
          55: lut_fn = 16'h00e5;
          56: lut_fn = 16'h00e8;
          57: lut_fn = 16'h00eb;
          58: lut_fn = 16'h00ee;
          59: lut_fn = 16'h00f1;
          60: lut_fn = 16'h00f4;
          61: lut_fn = 16'h00f7;
          62: lut_fn = 16'h00fa;
          63: lut_fn = 16'h00fd;
        default: lut_fn = 16'h0000;
      endcase
    end
  endfunction

  function [LOGW-1:0] fbitlen(input [XW-1:0] v);
    integer q;
    begin
      fbitlen = {LOGW{1'b0}};
      for (q = 0; q < XW; q = q + 1)
        if (v[q]) fbitlen = q[LOGW-1:0];
    end
  endfunction

  reg [LOGW-1:0] e_c; reg [BW-1:0] idx_c; reg [15:0] o_c;
  reg [NW-1:0] t, xw, two;
  always @(*) begin
    xw = {{(NW-XW){1'b0}}, in_x};
    e_c = {LOGW{1'b0}}; idx_c = {BW{1'b0}}; o_c = 16'd0; two = {NW{1'b0}};
    if (in_x != {XW{1'b0}}) begin
      e_c = fbitlen(in_x);
      two = ({{(NW-1){1'b0}}, 1'b1}) << e_c;
      t = (xw - two) << BW;
      t = t >> e_c;
      idx_c = t[BW-1:0];
      o_c = (e_c << FW) + lut_fn(idx_c);
    end
  end
  always @(posedge clk) begin
    if (!rst_n) begin out_valid <= 1'b0; out_l <= 16'd0; end
    else begin
      out_valid <= 1'b0;
      if (in_valid) begin out_l <= o_c; out_valid <= 1'b1; end
    end
  end
endmodule
