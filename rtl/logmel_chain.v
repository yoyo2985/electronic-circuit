//------------------------------------------------------------------------------
// logmel_chain.v   B3-4c：mel_bank → log2_lut 串链，产出定点 log-mel 能量
//   输入 NB 个功率 bin → 输出 M 个 log-mel。
//------------------------------------------------------------------------------
module logmel_chain #(
    parameter NB  = 9,
    parameter M   = 6,
    parameter CFQ = 12,
    parameter XW  = 48,
    parameter FW  = 8,
    parameter BW  = 6
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire [31:0]      in_pow,
    output wire             out_valid,
    output wire [15:0]      out_logmel
);
    wire mel_ok;
    wire [63:0] mel;

    mel_bank #(.NB(NB), .M(M), .CFQ(CFQ)) u_mel (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_pow(in_pow),
        .out_valid(mel_ok), .out_mel(mel)
    );

    log2_lut #(.XW(XW), .FW(FW), .BW(BW)) u_log (
        .clk(clk), .rst_n(rst_n), .in_valid(mel_ok), .in_x(mel[XW-1:0]),
        .out_valid(out_valid), .out_l(out_logmel)
    );
endmodule
