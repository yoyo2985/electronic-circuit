//------------------------------------------------------------------------------
// audio_status.v   调试用状态上报：每 500ms 无条件发一行（不依赖音频帧）
//   行格式（20 字节）：
//     'P' + 4 hex(帧数) + ' ' + 'L' + 4 hex(左能量) + ' ' + 'R' + 4 hex(右能量)
//     + ' ' + 'V'(0/1=VAD 语音活动) + '\n'
//   例："P5DC0 L1234 R0002 V1\n"
//   内部例化 uart_tx，沿用 busy 握手。帧计数 n 每 500ms 清零。
//------------------------------------------------------------------------------
module audio_status #(
    parameter BAUD_TICKS = 434,
    parameter VAL_W      = 16,
    parameter PERIOD_MS  = 500
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,        // 1ms 节拍
    input  wire       frame_ok,        // 每立体声对 1 拍（audio_pcm_bridge.pair_valid）
    input  wire [VAL_W-1:0] e_l,       // 左能量(avg 高 16 位)
    input  wire [VAL_W-1:0] e_r,       // 右能量
    input  wire       vad_in,          // VAD 语音活动(0/1)
    output wire       tx
);
    wire tx_busy;
    reg  send;
    reg  [7:0] byte_out;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(tx_busy)
    );

    // 帧计数 + 0.5s 定时
    reg [15:0] n;
    reg [15:0] n_snap;                 // 发一行期间锁存的帧数
    reg [9:0]  ms;
    reg        hb;                      // 该发一行了
    always @(posedge clk) begin
        if (!rst_n) begin
            n  <= 0; ms <= 0; hb <= 0; n_snap <= 0;
        end else begin
            hb <= 1'b0;
            if (frame_ok) n <= n + 1'b1;
            if (tick_1ms) begin
                if (ms == PERIOD_MS[9:0] - 1'b1) begin
                    ms <= 0; hb <= 1'b1; n_snap <= n; n <= 0;
                end else ms <= ms + 1'b1;
            end
        end
    end

    // 组合：帧内字节号 0..19 → ASCII
    reg [4:0]  bi;
    reg [3:0]  nib;
    always @(*) begin
        case (bi)
            5'd0 : byte_out = "P";
            5'd5 : byte_out = " ";
            5'd6 : byte_out = "L";
            5'd11: byte_out = " ";
            5'd12: byte_out = "R";
            5'd17: byte_out = " ";
            5'd18: byte_out = vad_in ? "1" : "0";
            5'd19: byte_out = "\n";
            default: begin
                if      (bi >= 1 && bi <= 4)  nib = n_snap[(3-(bi-1))*4 +: 4];
                else if (bi >= 7 && bi <= 10) nib = e_l[(3-(bi-7))*4 +: 4];
                else if (bi >= 13 && bi <= 16)nib = e_r[(3-(bi-13))*4 +: 4];
                else nib = 4'd0;
                byte_out = (nib < 4'd10) ? (8'h30 + nib) : (8'h37 + nib);
            end
        endcase
    end

    reg framing;
    reg sent;
    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            bi <= 5'd0; framing <= 1'b0; sent <= 1'b0;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (hb) begin framing <= 1'b1; bi <= 5'd0; end
            end else if (!sent) begin
                if (!tx_busy) begin send <= 1'b1; sent <= 1'b1; end
            end else begin
                if (!tx_busy) begin
                    sent <= 1'b0;
                    if (bi == 5'd19) framing <= 1'b0;
                    else             bi     <= bi + 1'b1;
                end
            end
        end
    end

endmodule
