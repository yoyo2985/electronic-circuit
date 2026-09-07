//------------------------------------------------------------------------------
// seven_seg.v   4 位动态扫描数码管（共阴）
//   板上：字码段高=点亮；片选低=选中。
//   seg[7:0] = {DOT,G,F,E,D,C,B,A}，逐位对应 Digitron_Out[7:0]
//   dig_cs[3:0] 低有效：dig_cs[0]=COM4(最右) … dig_cs[3]=COM1(最左)
//   扫描节拍 tick_scan 接 clock_enable 的 tick_1ms（1 ms/位 ⇒ 250 Hz/位，不闪）
// 复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module seven_seg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_scan,    // 扫描节拍（来自 clock_enable）
    input  wire [15:0] bcd_data,     // 4 位 BCD：[3:0]=个位(最右) … [15:12]=千位(最左)
    input  wire [3:0]  points,       // 小数点：bit 对应各位，1=点亮
    input  wire [3:0]  blank,        // 消隐：bit 对应各位，1=该位不显示（可消隐前导 0）
    output reg  [7:0]  seg,          // 接 Digitron_Out[7:0]
    output reg  [3:0]  dig_cs        // 接 DigitronCS_Out[3:0]
);
    // 当前扫描位索引 0..3
    reg [1:0] dig_idx;
    always @(posedge clk) begin
        if (!rst_n)
            dig_idx <= 2'd0;
        else if (tick_scan)
            dig_idx <= dig_idx + 2'd1;   // 2 位自然回绕 0→1→2→3→0
    end

    // 取出当前位的 BCD / 小数点 / 消隐（组合逻辑）
    reg [3:0] cur_bcd;
    reg       cur_point;
    reg       cur_blank;
    always @(*) begin
        case (dig_idx)
            2'd0: begin cur_bcd = bcd_data[3:0];   cur_point = points[0]; cur_blank = blank[0]; end
            2'd1: begin cur_bcd = bcd_data[7:4];   cur_point = points[1]; cur_blank = blank[1]; end
            2'd2: begin cur_bcd = bcd_data[11:8];  cur_point = points[2]; cur_blank = blank[2]; end
            2'd3: begin cur_bcd = bcd_data[15:12]; cur_point = points[3]; cur_blank = blank[3]; end
            default: begin cur_bcd = 4'd0; cur_point = 1'b0; cur_blank = 1'b1; end
        endcase
    end

    // 七段字形（共阴，高=亮） {DOT,G,F,E,D,C,B,A}
    reg [7:0] font;
    always @(*) begin
        case (cur_bcd)
            4'd0: font = 8'h3F;
            4'd1: font = 8'h06;
            4'd2: font = 8'h5B;
            4'd3: font = 8'h4F;
            4'd4: font = 8'h66;
            4'd5: font = 8'h6D;
            4'd6: font = 8'h7D;
            4'd7: font = 8'h07;
            4'd8: font = 8'h7F;
            4'd9: font = 8'h6F;
            default: font = 8'h00;   // 非法 BCD 暂按消隐（如需 A..F 字母后续扩展）
        endcase
    end

    // 输出：消隐则全灭；否则字形 + 小数点（bit7=DOT）
    always @(*) begin
        seg    = cur_blank ? 8'h00 : (font | (cur_point ? 8'h80 : 8'h00));
        dig_cs = 4'b1111;            // 默认全不选
        dig_cs[dig_idx] = 1'b0;      // 选中当前位（低有效）
    end
endmodule
