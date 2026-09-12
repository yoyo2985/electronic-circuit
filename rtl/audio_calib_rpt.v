//------------------------------------------------------------------------------
// audio_calib_rpt.v   校准固件数值上报：每 PERIOD_MS 发一行 ASCII(不经[AA])
//   行格式(27 字节):
//     'P' + 6hex(帧峰值) + ' ' + 'L' + 6hex(左窗均值) + ' ' + 'R' + 6hex(右窗均值)
//     + ' ' + 'V' + (0/1) + '\n'
//   例: "P0F3A12 L001123 R000E87 V1\n"
//   字段宽 24bit(6 hex)：噪声底 ~2^16(0x010000)仍可分辨，4 hex 会饱和。
//   peak = audio_vad 帧峰值(max|L|,|R|) —— 与 VAD 阈值同口径，用来定 TH_ON/TH_OFF。
//   avgL/R = audio_energy 窗均值幅度。
//   用 SSCOM/串口终端(115200)抓数：静音一段 / 说话一段 / 拍手，取数值区间。
//------------------------------------------------------------------------------
module audio_calib_rpt #(
    parameter BAUD_TICKS = 434,
    parameter PERIOD_MS  = 200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,
    input  wire [23:0] pk,            // 帧峰值(24bit)
    input  wire [23:0] avg_l,         // 左窗均值(24bit)
    input  wire [23:0] avg_r,         // 右窗均值(24bit)
    input  wire       vad_in,
    output wire       tx
);
    wire tx_busy;
    reg  send;
    reg  [7:0] byte_out;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(tx_busy)
    );

    reg [9:0] ms;
    reg       hb;
    reg [23:0] pk_s, al_s, ar_s;
    always @(posedge clk) begin
        if (!rst_n) begin
            ms <= 10'd0; hb <= 1'b0;
            pk_s <= 0; al_s <= 0; ar_s <= 0;
        end else begin
            hb <= 1'b0;
            if (tick_1ms) begin
                if (ms == PERIOD_MS[9:0] - 1'b1) begin
                    ms <= 10'd0; hb <= 1'b1;
                    pk_s <= pk; al_s <= avg_l; ar_s <= avg_r;
                end else ms <= ms + 1'b1;
            end
        end
    end

    function [7:0] hexc(input [3:0] n);
        hexc = (n < 4'd10) ? (8'h30 + n) : (8'h37 + n);
    endfunction

    // 第 d 个 hex 位(0=最高位, L-1=最低位)取自值 v[(L-1-d)*4 +:4]
    function [3:0] digit(input [23:0] v, input [2:0] d);
        digit = v[(3'd5 - d) * 4 +: 4];
    endfunction

    reg [4:0] bi;
    reg [3:0] nib;
    reg [7:0] cb;
    always @(*) begin
        case (bi)
            5'd0 : cb = "P";
            5'd7 : cb = " ";
            5'd8 : cb = "L";
            5'd15: cb = " ";
            5'd16: cb = "R";
            5'd23: cb = " ";
            5'd24: cb = "V";
            5'd25: cb = vad_in ? "1" : "0";
            5'd26: cb = "\n";
            default: begin
                if      (bi >= 1  && bi <= 6)  nib = digit(pk_s, (bi - 5'd1));
                else if (bi >= 9  && bi <= 14) nib = digit(al_s, (bi - 5'd9));
                else if (bi >= 17 && bi <= 22) nib = digit(ar_s, (bi - 5'd17));
                else nib = 4'd0;
                cb = hexc(nib);
            end
        endcase
    end
    always @(posedge clk) byte_out <= cb;

    reg framing, sent;
    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            framing <= 1'b0; sent <= 1'b0; bi <= 5'd0;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (hb) begin framing <= 1'b1; bi <= 5'd0; end
            end else if (!sent) begin
                if (!tx_busy) begin send <= 1'b1; sent <= 1'b1; end
            end else begin
                if (!tx_busy) begin
                    sent <= 1'b0;
                    if (bi == 5'd26) framing <= 1'b0;
                    else             bi <= bi + 1'b1;
                end
            end
        end
    end
endmodule
