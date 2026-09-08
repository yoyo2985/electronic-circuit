//------------------------------------------------------------------------------
// uart_telemetry.v   遥测帧发送（15）
//   每 TELEM_MS 毫秒经 UART 发一帧 5 字节：
//     [0] 0xAA(帧头) [1] state [2] target [3] pos [4] chk
//   其中 target/pos 取低 8 位(0..180<256)；chk = 0xAA^state^target^pos。
//   内部例化 uart_tx（单字节帧格式 115200）。fbyte_ok 每次派发字节给 uart 时给 1 拍
//   （可用来仿真核对/调试）。
// 参数化：TELEM_MS / BAUD_TICKS。复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module uart_telemetry #(
    parameter TELEM_MS    = 100,     // 毫秒（用 1ms tick 数）
    parameter BAUD_TICKS  = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,
    input  wire [7:0] state,         // 运行状态（FSM state）
    input  wire [9:0] target,
    input  wire [9:0] pos,
    output wire       tx,            // 串行输出
    output reg  [7:0] fbyte,         // 当前派发字节（调试/核对）
    output reg        fbyte_ok       // 派发脉冲
);
    wire tx_busy;
    reg send;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(fbyte), .tx(tx), .busy(tx_busy)
    );

    reg [15:0] ms;                   // 帧间隔计数
    reg [2:0]  bi;                   // 帧内字节序号 0..4
    reg        framing;              // 正在发一帧
    reg        sent;                 // 当前字节已交给 uart_tx，等待发完

    always @(posedge clk) begin
        send     <= 1'b0;
        fbyte_ok <= 1'b0;
        if (!rst_n) begin
            ms      <= 16'd0;
            bi      <= 3'd0;
            framing <= 1'b0;
            sent    <= 1'b0;
            fbyte   <= 8'h00;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (tick_1ms) begin
                    if (ms >= TELEM_MS - 1) begin
                        ms      <= 16'd0;
                        framing <= 1'b1;
                        bi      <= 3'd0;
                    end else
                        ms <= ms + 16'd1;
                end
            end else if (!sent) begin
                // 本字节尚未派发：等 uart_tx 空闲时派发一次（一拍脉冲）
                if (!tx_busy) begin
                    case (bi)
                        3'd0: fbyte <= 8'hAA;
                        3'd1: fbyte <= state;
                        3'd2: fbyte <= target[7:0];
                        3'd3: fbyte <= pos[7:0];
                        default: fbyte <= 8'hAA ^ state ^ target[7:0] ^ pos[7:0];
                    endcase
                    send     <= 1'b1;
                    fbyte_ok <= 1'b1;
                    sent     <= 1'b1;
                end
            end else begin
                // 已派发：等 uart_tx 发完本字节（busy 回落）再推进序号
                if (!tx_busy) begin
                    sent <= 1'b0;
                    if (bi == 3'd4) framing <= 1'b0;   // 最后一字节，发完帧结束
                    else            bi <= bi + 1'b1;
                end
            end
        end
    end
endmodule
