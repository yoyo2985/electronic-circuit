//------------------------------------------------------------------------------
// audio_rpt.v   把左右能量以 ASCII 行经 UART 发出（便于串口终端直接读）
//   行格式（12 字节）：
//     'L' + v_l 高→低 4 个 hex 字符 + ' ' + 'R' + v_r 4 hex + '\n'
//   例：avg_l=0x1234、avg_r=0xabcd → "L1234 Rabcd\n"
//   每 trigger(=audio_energy.win_done) 发一行；发送中再来的 trigger 丢弃
//   （一行约 1ms @115200 << 21ms 窗口，不会丢窗口）。
//   内部例化 uart_tx，沿用 busy 握手派发字节（同 uart_telemetry 修复后写法）。
//------------------------------------------------------------------------------
module audio_rpt #(
    parameter BAUD_TICKS = 434,     // 115200
    parameter VAL_W      = 16
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       trigger,       // 上报请求（1 拍）
    input  wire [VAL_W-1:0] v_l,
    input  wire [VAL_W-1:0] v_r,
    output wire       tx
);
    wire tx_busy;
    reg  send;
    reg  [7:0] byte_out;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(tx_busy)
    );

    // 组合：当前帧内字节号 0..11 → 该字节的 ASCII
    reg [3:0] bi;                  // byte index
    reg [3:0] nib;
    always @(*) begin
        case (bi)
            4'd0 : byte_out = "L";
            4'd5 : byte_out = " ";
            4'd6 : byte_out = "R";
            4'd11: byte_out = "\n";
            default: begin
                // 1..4 来自 v_l，7..10 来自 v_r；高→低取 nibble
                if (bi >= 1 && bi <= 4)      nib = v_l[(3-(bi-1))*4 +: 4];
                else if (bi >= 7 && bi <= 10) nib = v_r[(3-(bi-7))*4 +: 4];
                else nib = 4'd0;
                byte_out = (nib < 4'd10) ? (8'h30 + nib) : (8'h37 + nib); // '0'/'A'
            end
        endcase
    end

    reg framing;                   // 正在发一行
    reg sent;                      // 当前字节已派发，等 uart_tx 发完

    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            bi      <= 4'd0;
            framing <= 1'b0;
            sent    <= 1'b0;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (trigger) begin
                    framing <= 1'b1;
                    bi      <= 4'd0;
                end
            end else if (!sent) begin
                if (!tx_busy) begin
                    send   <= 1'b1;     // 派发当前字节（byte_out 由 bi 组合给出）
                    sent   <= 1'b1;
                end
            end else begin
                if (!tx_busy) begin     // 上一字节发完再推下一字节
                    sent <= 1'b0;
                    if (bi == 4'd11) framing <= 1'b0;
                    else             bi     <= bi + 1'b1;
                end
            end
        end
    end

endmodule
