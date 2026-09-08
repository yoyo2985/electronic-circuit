//------------------------------------------------------------------------------
// mfcc_quant.v   B5.2 MFCC 32→16 定标：sat16( v >>> QS )
//   QS：由 Python 对 owner MFCC 统计选(默认 0=B4 现尺度)；负数为算术右移(与 py >> 一致)。
//   禁止裸截断——超出 int16 一律饱和。可综合整数实现。
//------------------------------------------------------------------------------
module mfcc_quant #(
    parameter IW = 32,
    parameter OW = 16,
    parameter QS = 0
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire signed [IW-1:0] in_val,
    output reg              out_valid,
    output reg  signed [OW-1:0] out_q
);
    localparam signed [IW+2:0] MINV = -(1 << (OW - 1));
    localparam signed [IW+2:0] MAXV = (1 << (OW - 1)) - 1;
    reg signed [IW+2:0] s;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_q     <= {OW{1'b0}};
            s         <= 0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                s = $signed(in_val) >>> QS;
                if (s > MAXV)      out_q <= MAXV[OW-1:0];
                else if (s < MINV) out_q <= MINV[OW-1:0];
                else               out_q <= s[OW-1:0];
                out_valid <= 1'b1;
            end
        end
    end
endmodule
