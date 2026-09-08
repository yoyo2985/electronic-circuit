//------------------------------------------------------------------------------
// log2_lut.v   B3-4b 定点 log2 近似（位扫描 + 尾数 LUT）
//   对正整数 x：e=floor(log2 x)；idx=((x-2^e)<<BW)>>e；
//              out=(e<<FW)+LUT[idx]，LUT[k]=round(log2(1+k/2^BW)*2^FW)。
//   x=0 → out=0。与 py/gen_log_vec.py 的整数镜像逐位一致。
//   输入 XW 位、输出 FW+e 位。复位：同步低有效。
//------------------------------------------------------------------------------
module log2_lut #(
    parameter XW = 48,
    parameter FW = 8,
    parameter BW = 6
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire [XW-1:0]    in_x,
    output reg              out_valid,
    output reg  [15:0]      out_l
);
    localparam LOGW = $clog2(XW + 1);       // 放得下 e
    localparam LF_W = 8 + 6;                 // (FW+BW) 尾数小数分辨率占位
    localparam NW   = XW + BW + 8;           // 中间位宽

    reg [15:0] lut[0:(1<<BW)-1];
    initial $readmemh("data/log2_lut.mem", lut);

    function [LOGW-1:0] fbitlen(input [XW-1:0] v);
        integer q;
        begin
            fbitlen = {LOGW{1'b0}};
            for (q = XW - 1; q >= 0; q = q - 1)
                if (v[q]) begin
                    fbitlen = q[LOGW-1:0];
                    q = -1;                 // 提前退出
                end
        end
    endfunction

    reg [LOGW-1:0] e_c;
    reg [BW-1:0]   idx_c;
    reg [15:0]     o_c;
    reg [NW-1:0]   t, xw, two;

    always @(*) begin
        xw = {{(NW-XW){1'b0}}, in_x};
        e_c = {LOGW{1'b0}}; idx_c = {BW{1'b0}}; o_c = 16'd0; two = {NW{1'b0}};
        if (in_x != {XW{1'b0}}) begin
            e_c = fbitlen(in_x);
            two = ({{(NW-1){1'b0}}, 1'b1}) << e_c;   // 2^e
            t   = (xw - two) << BW;
            t   = t >> e_c;                          // >=0，逻辑右移
            idx_c = t[BW-1:0];
            o_c   = (e_c << FW) + lut[idx_c];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_l     <= 16'd0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                out_l     <= o_c;
                out_valid <= 1'b1;
            end
        end
    end
endmodule
