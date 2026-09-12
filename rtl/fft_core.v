// fft_core.v  radix-2 迭代定点 FFT(DIT) —— 块RAM版(蝶形顺序/算术/tw 不变)
//   re/im 各用一块 64x32 单口块RAM(IP fft_ram_64x32)。块RAM 读有固定延迟,
//   故每个读把地址稳住 RD=4 拍再采样(对 1~4 拍延迟都成立, 不必知道确切值)。
//   蝶形: 读 Xa(实虚)→读 Xb(实虚)→算 t=w*Xb>>15、Xa±t>>1→写 Xa→写 Xb。
//   输出自然频率序 k, 与逐位参考一致。仿真用 sim/audio_sim/fft_ram_64x32_sim.v。
module fft_core #(parameter AW=24, parameter N=64)(
  input wire clk, input wire rst_n,
  input wire in_valid, input wire signed [AW-1:0] in_re,
  output reg out_valid, output reg signed [31:0] out_re, output reg signed [31:0] out_im);
  localparam LOG=$clog2(N); localparam NB=(N>>1)*LOG;
  localparam LOGN=$clog2(N+1); localparam LOGNB=$clog2(NB+1);
  localparam RD=6;                 // 读稳拍数(>= 块RAM延迟上限)
  function signed [15:0] twre_fn(input integer a);
    begin
      case (a)
          0: twre_fn = 16'sh7fff;
          1: twre_fn = 16'sh7f62;
          2: twre_fn = 16'sh7d8a;
          3: twre_fn = 16'sh7a7d;
          4: twre_fn = 16'sh7642;
          5: twre_fn = 16'sh70e3;
          6: twre_fn = 16'sh6a6e;
          7: twre_fn = 16'sh62f2;
          8: twre_fn = 16'sh5a82;
          9: twre_fn = 16'sh5134;
          10: twre_fn = 16'sh471d;
          11: twre_fn = 16'sh3c57;
          12: twre_fn = 16'sh30fc;
          13: twre_fn = 16'sh2528;
          14: twre_fn = 16'sh18f9;
          15: twre_fn = 16'sh0c8c;
          16: twre_fn = 16'sh0000;
          17: twre_fn = 16'shf374;
          18: twre_fn = 16'she707;
          19: twre_fn = 16'shdad8;
          20: twre_fn = 16'shcf04;
          21: twre_fn = 16'shc3a9;
          22: twre_fn = 16'shb8e3;
          23: twre_fn = 16'shaecc;
          24: twre_fn = 16'sha57e;
          25: twre_fn = 16'sh9d0e;
          26: twre_fn = 16'sh9592;
          27: twre_fn = 16'sh8f1d;
          28: twre_fn = 16'sh89be;
          29: twre_fn = 16'sh8583;
          30: twre_fn = 16'sh8276;
          31: twre_fn = 16'sh809e;
          32: twre_fn = 16'sh8001;
          33: twre_fn = 16'sh809e;
          34: twre_fn = 16'sh8276;
          35: twre_fn = 16'sh8583;
          36: twre_fn = 16'sh89be;
          37: twre_fn = 16'sh8f1d;
          38: twre_fn = 16'sh9592;
          39: twre_fn = 16'sh9d0e;
          40: twre_fn = 16'sha57e;
          41: twre_fn = 16'shaecc;
          42: twre_fn = 16'shb8e3;
          43: twre_fn = 16'shc3a9;
          44: twre_fn = 16'shcf04;
          45: twre_fn = 16'shdad8;
          46: twre_fn = 16'she707;
          47: twre_fn = 16'shf374;
          48: twre_fn = 16'sh0000;
          49: twre_fn = 16'sh0c8c;
          50: twre_fn = 16'sh18f9;
          51: twre_fn = 16'sh2528;
          52: twre_fn = 16'sh30fc;
          53: twre_fn = 16'sh3c57;
          54: twre_fn = 16'sh471d;
          55: twre_fn = 16'sh5134;
          56: twre_fn = 16'sh5a82;
          57: twre_fn = 16'sh62f2;
          58: twre_fn = 16'sh6a6e;
          59: twre_fn = 16'sh70e3;
          60: twre_fn = 16'sh7642;
          61: twre_fn = 16'sh7a7d;
          62: twre_fn = 16'sh7d8a;
          63: twre_fn = 16'sh7f62;
        default: twre_fn = 16'sh0000;
      endcase
    end
  endfunction
  function signed [15:0] twim_fn(input integer a);
    begin
      case (a)
          0: twim_fn = 16'sh0000;
          1: twim_fn = 16'shf374;
          2: twim_fn = 16'she707;
          3: twim_fn = 16'shdad8;
          4: twim_fn = 16'shcf04;
          5: twim_fn = 16'shc3a9;
          6: twim_fn = 16'shb8e3;
          7: twim_fn = 16'shaecc;
          8: twim_fn = 16'sha57e;
          9: twim_fn = 16'sh9d0e;
          10: twim_fn = 16'sh9592;
          11: twim_fn = 16'sh8f1d;
          12: twim_fn = 16'sh89be;
          13: twim_fn = 16'sh8583;
          14: twim_fn = 16'sh8276;
          15: twim_fn = 16'sh809e;
          16: twim_fn = 16'sh8001;
          17: twim_fn = 16'sh809e;
          18: twim_fn = 16'sh8276;
          19: twim_fn = 16'sh8583;
          20: twim_fn = 16'sh89be;
          21: twim_fn = 16'sh8f1d;
          22: twim_fn = 16'sh9592;
          23: twim_fn = 16'sh9d0e;
          24: twim_fn = 16'sha57e;
          25: twim_fn = 16'shaecc;
          26: twim_fn = 16'shb8e3;
          27: twim_fn = 16'shc3a9;
          28: twim_fn = 16'shcf04;
          29: twim_fn = 16'shdad8;
          30: twim_fn = 16'she707;
          31: twim_fn = 16'shf374;
          32: twim_fn = 16'sh0000;
          33: twim_fn = 16'sh0c8c;
          34: twim_fn = 16'sh18f9;
          35: twim_fn = 16'sh2528;
          36: twim_fn = 16'sh30fc;
          37: twim_fn = 16'sh3c57;
          38: twim_fn = 16'sh471d;
          39: twim_fn = 16'sh5134;
          40: twim_fn = 16'sh5a82;
          41: twim_fn = 16'sh62f2;
          42: twim_fn = 16'sh6a6e;
          43: twim_fn = 16'sh70e3;
          44: twim_fn = 16'sh7642;
          45: twim_fn = 16'sh7a7d;
          46: twim_fn = 16'sh7d8a;
          47: twim_fn = 16'sh7f62;
          48: twim_fn = 16'sh7fff;
          49: twim_fn = 16'sh7f62;
          50: twim_fn = 16'sh7d8a;
          51: twim_fn = 16'sh7a7d;
          52: twim_fn = 16'sh7642;
          53: twim_fn = 16'sh70e3;
          54: twim_fn = 16'sh6a6e;
          55: twim_fn = 16'sh62f2;
          56: twim_fn = 16'sh5a82;
          57: twim_fn = 16'sh5134;
          58: twim_fn = 16'sh471d;
          59: twim_fn = 16'sh3c57;
          60: twim_fn = 16'sh30fc;
          61: twim_fn = 16'sh2528;
          62: twim_fn = 16'sh18f9;
          63: twim_fn = 16'sh0c8c;
        default: twim_fn = 16'sh0000;
      endcase
    end
  endfunction

  // ---- 两块 64x32 单口块RAM (re=实部, im=虚部) ----
  wire [31:0] re_q, im_q;
  reg  [31:0] re_d, im_d;
  reg  [5:0]  ram_addr;
  reg         ram_we;
  fft_ram_64x32 u_re (.doa(re_q), .dia(re_d), .addra(ram_addr),
                      .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(ram_we), .rsta(1'b0));
  fft_ram_64x32 u_im (.doa(im_q), .dia(im_d), .addra(ram_addr),
                      .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(ram_we), .rsta(1'b0));

  localparam [2:0] S_LOAD=0, S_RUN=1, S_OUT=2;
  reg [1:0] st;
  reg [LOGN-1:0] cnt;
  reg [LOGNB-1:0] bb;
  reg [5:0] t;                     // 蝶形/输出子步
  reg [LOGN-1:0] wo;               // S_OUT 词计数
  reg [31:0] ra, ia, rb, ib;
  reg [31:0] na_re, na_im, nb_re, nb_im;
  reg signed [63:0] tr, ti;

  // 蝶形参数
  wire [LOG-1:0] stage_w = bb >> (LOG-1);
  wire [LOG-2:0] qw = bb[LOG-2:0];
  wire [LOG-1:0] half = 1 << stage_w;
  wire [LOG-1:0] g = qw >> stage_w;
  wire [LOG-1:0] j = qw & (half-1);
  wire [LOG-1:0] kbase = g << (stage_w+1);
  wire [LOG-1:0] addr_a = kbase + j;
  wire [LOG-1:0] addr_b = addr_a + half;
  wire [LOG-1:0] t_idx = j << (LOG-1-stage_w);

  // 蝶形子步常量
  localparam [5:0] B_RA=0;          // 读Xa段 0..RD-1
  localparam [5:0] B_RB=RD;         // 读Xb段 RD..2RD-1
  localparam [5:0] B_CALC=2*RD;     // 计算
  localparam [5:0] B_WA=2*RD+1;     // 写Xa
  localparam [5:0] B_WB=2*RD+2;     // 写Xb
  localparam [5:0] B_ADV=2*RD+3;    // 推进
  localparam [5:0] B_END=2*RD+4;

  always @(posedge clk) begin : proc
    if (!rst_n) begin
      st<=S_LOAD; cnt<={LOGN{1'b0}}; bb<={LOGNB{1'b0}}; t<=0; wo<={LOGN{1'b0}};
      out_valid<=1'b0; out_re<=32'sd0; out_im<=32'sd0;
      ra<=32'sd0; ia<=32'sd0; rb<=32'sd0; ib<=32'sd0;
      na_re<=0; na_im<=0; nb_re<=0; nb_im<=0; tr<=0; ti<=0;
    end else begin
      out_valid<=1'b0;
      case (st)
        S_LOAD: begin
          t<=0;
          if (in_valid) begin
            ram_addr<=cnt; re_d<={{ (32-AW){in_re[AW-1]} }, in_re}; im_d<=32'sd0; ram_we<=1'b1;
            if (cnt == N[LOGN-1:0]-1'b1) begin cnt<={LOGN{1'b0}}; bb<={LOGNB{1'b0}}; st<=S_RUN; end
            else cnt<=cnt+1'b1;
          end else ram_we<=1'b0;
        end
        S_RUN: begin
          ram_we<=1'b0;
          if (t==0) begin ram_addr<=addr_a; end
          // 读Xa: 0..RD-1, 末拍采 re_q/im_q(地址已稳RD拍)
          if (t < RD) begin
            if (t==RD-1) begin ra<=re_q; ia<=im_q; end
            t<=t+1;
          end
          else if (t < 2*RD) begin        // 读Xb
            if (t==RD) ram_addr<=addr_b;
            if (t==2*RD-1) begin rb<=re_q; ib<=im_q; end
            t<=t+1;
          end
          else if (t==B_CALC) begin
            tr = ($signed(rb)*twre_fn(t_idx) - $signed(ib)*twim_fn(t_idx)) >>> 15;
            ti = ($signed(rb)*twim_fn(t_idx) + $signed(ib)*twre_fn(t_idx)) >>> 15;
            na_re <= ($signed(ra)+tr) >>> 1; na_im <= ($signed(ia)+ti) >>> 1;
            nb_re <= ($signed(ra)-tr) >>> 1; nb_im <= ($signed(ia)-ti) >>> 1;
            t<=t+1;
          end
          else if (t==B_WA) begin
            ram_addr<=addr_a; re_d<=na_re; im_d<=na_im; ram_we<=1'b1;
            t<=t+1;
          end
          else if (t==B_WB) begin
            ram_addr<=addr_b; re_d<=nb_re; im_d<=nb_im; ram_we<=1'b1;
            t<=t+1;
          end
          else if (t==B_ADV) begin
            if (bb == NB[LOGNB-1:0]-1'b1) begin bb<={LOGNB{1'b0}}; cnt<={LOGN{1'b0}}; wo<=0; st<=S_OUT; end
            else bb<=bb+1'b1;
            t<=0;
          end
          else t<=t+1;   // B_WA/B_WB 的下沿(wea 已置, 保持1拍后清)
        end
        S_OUT: begin
          ram_we<=1'b0;
          if (t==0) ram_addr<=wo;                 // 发起读词 wo
          if (t < RD-1) begin t<=t+1; end
          else if (t==RD-1) begin
            out_re<=re_q; out_im<=im_q; out_valid<=1'b1;
            if (wo == N[LOGN-1:0]-1'b1) begin wo<=0; t<=0; st<=S_LOAD; end
            else begin wo<=wo+1'b1; t<=0; end
          end
        end
        default: st<=S_LOAD;
      endcase
    end
  end
endmodule
