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
  function signed [15:0] basis_fn(input integer a);
    begin
      case (a)
          0: basis_fn = 16'sh0394;
          1: basis_fn = 16'sh0394;
          2: basis_fn = 16'sh0394;
          3: basis_fn = 16'sh0394;
          4: basis_fn = 16'sh0394;
          5: basis_fn = 16'sh0394;
          6: basis_fn = 16'sh0394;
          7: basis_fn = 16'sh0394;
          8: basis_fn = 16'sh0394;
          9: basis_fn = 16'sh0394;
          10: basis_fn = 16'sh0394;
          11: basis_fn = 16'sh0394;
          12: basis_fn = 16'sh0394;
          13: basis_fn = 16'sh0394;
          14: basis_fn = 16'sh0394;
          15: basis_fn = 16'sh0394;
          16: basis_fn = 16'sh0394;
          17: basis_fn = 16'sh0394;
          18: basis_fn = 16'sh0394;
          19: basis_fn = 16'sh0394;
          20: basis_fn = 16'sh050b;
          21: basis_fn = 16'sh04eb;
          22: basis_fn = 16'sh04ad;
          23: basis_fn = 16'sh0450;
          24: basis_fn = 16'sh03d9;
          25: basis_fn = 16'sh0349;
          26: basis_fn = 16'sh02a5;
          27: basis_fn = 16'sh01f0;
          28: basis_fn = 16'sh012e;
          29: basis_fn = 16'sh0066;
          30: basis_fn = 16'shff9a;
          31: basis_fn = 16'shfed2;
          32: basis_fn = 16'shfe10;
          33: basis_fn = 16'shfd5b;
          34: basis_fn = 16'shfcb7;
          35: basis_fn = 16'shfc27;
          36: basis_fn = 16'shfbb0;
          37: basis_fn = 16'shfb53;
          38: basis_fn = 16'shfb15;
          39: basis_fn = 16'shfaf5;
          40: basis_fn = 16'sh04ff;
          41: basis_fn = 16'sh0482;
          42: basis_fn = 16'sh0394;
          43: basis_fn = 16'sh024c;
          44: basis_fn = 16'sh00cb;
          45: basis_fn = 16'shff35;
          46: basis_fn = 16'shfdb4;
          47: basis_fn = 16'shfc6c;
          48: basis_fn = 16'shfb7e;
          49: basis_fn = 16'shfb01;
          50: basis_fn = 16'shfb01;
          51: basis_fn = 16'shfb7e;
          52: basis_fn = 16'shfc6c;
          53: basis_fn = 16'shfdb4;
          54: basis_fn = 16'shff35;
          55: basis_fn = 16'sh00cb;
          56: basis_fn = 16'sh024c;
          57: basis_fn = 16'sh0394;
          58: basis_fn = 16'sh0482;
          59: basis_fn = 16'sh04ff;
          60: basis_fn = 16'sh04eb;
          61: basis_fn = 16'sh03d9;
          62: basis_fn = 16'sh01f0;
          63: basis_fn = 16'shff9a;
          64: basis_fn = 16'shfd5b;
          65: basis_fn = 16'shfbb0;
          66: basis_fn = 16'shfaf5;
          67: basis_fn = 16'shfb53;
          68: basis_fn = 16'shfcb7;
          69: basis_fn = 16'shfed2;
          70: basis_fn = 16'sh012e;
          71: basis_fn = 16'sh0349;
          72: basis_fn = 16'sh04ad;
          73: basis_fn = 16'sh050b;
          74: basis_fn = 16'sh0450;
          75: basis_fn = 16'sh02a5;
          76: basis_fn = 16'sh0066;
          77: basis_fn = 16'shfe10;
          78: basis_fn = 16'shfc27;
          79: basis_fn = 16'shfb15;
          80: basis_fn = 16'sh04d0;
          81: basis_fn = 16'sh02f9;
          82: basis_fn = 16'sh0000;
          83: basis_fn = 16'shfd07;
          84: basis_fn = 16'shfb30;
          85: basis_fn = 16'shfb30;
          86: basis_fn = 16'shfd07;
          87: basis_fn = 16'sh0000;
          88: basis_fn = 16'sh02f9;
          89: basis_fn = 16'sh04d0;
          90: basis_fn = 16'sh04d0;
          91: basis_fn = 16'sh02f9;
          92: basis_fn = 16'sh0000;
          93: basis_fn = 16'shfd07;
          94: basis_fn = 16'shfb30;
          95: basis_fn = 16'shfb30;
          96: basis_fn = 16'shfd07;
          97: basis_fn = 16'sh0000;
          98: basis_fn = 16'sh02f9;
          99: basis_fn = 16'sh04d0;
          100: basis_fn = 16'sh04ad;
          101: basis_fn = 16'sh01f0;
          102: basis_fn = 16'shfe10;
          103: basis_fn = 16'shfb53;
          104: basis_fn = 16'shfb53;
          105: basis_fn = 16'shfe10;
          106: basis_fn = 16'sh01f0;
          107: basis_fn = 16'sh04ad;
          108: basis_fn = 16'sh04ad;
          109: basis_fn = 16'sh01f0;
          110: basis_fn = 16'shfe10;
          111: basis_fn = 16'shfb53;
          112: basis_fn = 16'shfb53;
          113: basis_fn = 16'shfe10;
          114: basis_fn = 16'sh01f0;
          115: basis_fn = 16'sh04ad;
          116: basis_fn = 16'sh04ad;
          117: basis_fn = 16'sh01f0;
          118: basis_fn = 16'shfe10;
          119: basis_fn = 16'shfb53;
          120: basis_fn = 16'sh0482;
          121: basis_fn = 16'sh00cb;
          122: basis_fn = 16'shfc6c;
          123: basis_fn = 16'shfb01;
          124: basis_fn = 16'shfdb4;
          125: basis_fn = 16'sh024c;
          126: basis_fn = 16'sh04ff;
          127: basis_fn = 16'sh0394;
          128: basis_fn = 16'shff35;
          129: basis_fn = 16'shfb7e;
          130: basis_fn = 16'shfb7e;
          131: basis_fn = 16'shff35;
          132: basis_fn = 16'sh0394;
          133: basis_fn = 16'sh04ff;
          134: basis_fn = 16'sh024c;
          135: basis_fn = 16'shfdb4;
          136: basis_fn = 16'shfb01;
          137: basis_fn = 16'shfc6c;
          138: basis_fn = 16'sh00cb;
          139: basis_fn = 16'sh0482;
          140: basis_fn = 16'sh0450;
          141: basis_fn = 16'shff9a;
          142: basis_fn = 16'shfb53;
          143: basis_fn = 16'shfc27;
          144: basis_fn = 16'sh012e;
          145: basis_fn = 16'sh04eb;
          146: basis_fn = 16'sh0349;
          147: basis_fn = 16'shfe10;
          148: basis_fn = 16'shfaf5;
          149: basis_fn = 16'shfd5b;
          150: basis_fn = 16'sh02a5;
          151: basis_fn = 16'sh050b;
          152: basis_fn = 16'sh01f0;
          153: basis_fn = 16'shfcb7;
          154: basis_fn = 16'shfb15;
          155: basis_fn = 16'shfed2;
          156: basis_fn = 16'sh03d9;
          157: basis_fn = 16'sh04ad;
          158: basis_fn = 16'sh0066;
          159: basis_fn = 16'shfbb0;
          160: basis_fn = 16'sh0418;
          161: basis_fn = 16'shfe70;
          162: basis_fn = 16'shfaf1;
          163: basis_fn = 16'shfe70;
          164: basis_fn = 16'sh0418;
          165: basis_fn = 16'sh0418;
          166: basis_fn = 16'shfe70;
          167: basis_fn = 16'shfaf1;
          168: basis_fn = 16'shfe70;
          169: basis_fn = 16'sh0418;
          170: basis_fn = 16'sh0418;
          171: basis_fn = 16'shfe70;
          172: basis_fn = 16'shfaf1;
          173: basis_fn = 16'shfe70;
          174: basis_fn = 16'sh0418;
          175: basis_fn = 16'sh0418;
          176: basis_fn = 16'shfe70;
          177: basis_fn = 16'shfaf1;
          178: basis_fn = 16'shfe70;
          179: basis_fn = 16'sh0418;
          180: basis_fn = 16'sh03d9;
          181: basis_fn = 16'shfd5b;
          182: basis_fn = 16'shfb53;
          183: basis_fn = 16'sh012e;
          184: basis_fn = 16'sh050b;
          185: basis_fn = 16'sh0066;
          186: basis_fn = 16'shfb15;
          187: basis_fn = 16'shfe10;
          188: basis_fn = 16'sh0450;
          189: basis_fn = 16'sh0349;
          190: basis_fn = 16'shfcb7;
          191: basis_fn = 16'shfbb0;
          192: basis_fn = 16'sh01f0;
          193: basis_fn = 16'sh04eb;
          194: basis_fn = 16'shff9a;
          195: basis_fn = 16'shfaf5;
          196: basis_fn = 16'shfed2;
          197: basis_fn = 16'sh04ad;
          198: basis_fn = 16'sh02a5;
          199: basis_fn = 16'shfc27;
          200: basis_fn = 16'sh0394;
          201: basis_fn = 16'shfc6c;
          202: basis_fn = 16'shfc6c;
          203: basis_fn = 16'sh0394;
          204: basis_fn = 16'sh0394;
          205: basis_fn = 16'shfc6c;
          206: basis_fn = 16'shfc6c;
          207: basis_fn = 16'sh0394;
          208: basis_fn = 16'sh0394;
          209: basis_fn = 16'shfc6c;
          210: basis_fn = 16'shfc6c;
          211: basis_fn = 16'sh0394;
          212: basis_fn = 16'sh0394;
          213: basis_fn = 16'shfc6c;
          214: basis_fn = 16'shfc6c;
          215: basis_fn = 16'sh0394;
          216: basis_fn = 16'sh0394;
          217: basis_fn = 16'shfc6c;
          218: basis_fn = 16'shfc6c;
          219: basis_fn = 16'sh0394;
          220: basis_fn = 16'sh0349;
          221: basis_fn = 16'shfbb0;
          222: basis_fn = 16'shfe10;
          223: basis_fn = 16'sh04eb;
          224: basis_fn = 16'sh0066;
          225: basis_fn = 16'shfaf5;
          226: basis_fn = 16'sh012e;
          227: basis_fn = 16'sh04ad;
          228: basis_fn = 16'shfd5b;
          229: basis_fn = 16'shfc27;
          230: basis_fn = 16'sh03d9;
          231: basis_fn = 16'sh02a5;
          232: basis_fn = 16'shfb53;
          233: basis_fn = 16'shfed2;
          234: basis_fn = 16'sh050b;
          235: basis_fn = 16'shff9a;
          236: basis_fn = 16'shfb15;
          237: basis_fn = 16'sh01f0;
          238: basis_fn = 16'sh0450;
          239: basis_fn = 16'shfcb7;
          240: basis_fn = 16'sh02f9;
          241: basis_fn = 16'shfb30;
          242: basis_fn = 16'sh0000;
          243: basis_fn = 16'sh04d0;
          244: basis_fn = 16'shfd07;
          245: basis_fn = 16'shfd07;
          246: basis_fn = 16'sh04d0;
          247: basis_fn = 16'sh0000;
          248: basis_fn = 16'shfb30;
          249: basis_fn = 16'sh02f9;
          250: basis_fn = 16'sh02f9;
          251: basis_fn = 16'shfb30;
          252: basis_fn = 16'sh0000;
          253: basis_fn = 16'sh04d0;
          254: basis_fn = 16'shfd07;
          255: basis_fn = 16'shfd07;
          256: basis_fn = 16'sh04d0;
          257: basis_fn = 16'sh0000;
          258: basis_fn = 16'shfb30;
          259: basis_fn = 16'sh02f9;
        default: basis_fn = 16'sh0000;
      endcase
    end
  endfunction


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
                    prod = $signed(xbuf[m]) * $signed(basis_fn(k*M + m));
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
