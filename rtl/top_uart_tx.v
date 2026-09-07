//------------------------------------------------------------------------------
// top_uart_tx.v   06 UART 发送演示（顶层）
//   每隔 GAP_MS 毫秒向 TXD 发送一个 ASCII 数字字符 '0'..'9'，循环往复。
//   PC 用串口助手 115200,8,N,1 接收可看到 0~9 滚动。
//   LED3..0 同步显示当前发送的数字(0~9)。SW0(A9)=rst_n 拨上=运行。
//   发送节拍用 1ms tick 计数，不另造时钟域。
// 参数化：MS_DIV / BAUD_TICKS / GAP_MS（字间隔毫秒，仿真改小）。
//------------------------------------------------------------------------------
module top_uart_tx #(
    parameter MS_DIV    = 50000,
    parameter BAUD_TICKS = 434,
    parameter GAP_MS    = 200
) (
    input  wire       clk,
    input  wire       rst_n,
    output wire       tx,        // 接板上 TXD=D12
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    reg [3:0] digit;            // 0..9
    reg [15:0] wait_ms;         // 字间隔计数
    reg        sending;         // 当前帧是否在发
    reg        send;
    reg        busy_d1;
    wire       dut_tx_busy;
    wire       busy_fell = busy_d1 & ~dut_tx_busy;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(8'd48 + digit),    // '0'+digit
        .tx(tx), .busy(dut_tx_busy)
    );

    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            digit   <= 4'd0;
            wait_ms <= 16'd0;
            sending <= 1'b0;
            busy_d1 <= 1'b0;
        end else begin
            busy_d1 <= dut_tx_busy;
            if (busy_fell)          // 一帧发完
                sending <= 1'b0;
            if (!sending) begin
                if (wait_ms >= GAP_MS) begin
                    wait_ms <= 16'd0;
                    sending <= 1'b1;   // 启动下一帧
                    send    <= 1'b1;
                    if (digit == 4'd9) digit <= 4'd0;
                    else               digit <= digit + 4'd1;
                end else if (tick_1ms) begin
                    wait_ms <= wait_ms + 16'd1;
                end
            end
        end
    end

    assign led = {4'b0000, digit};
endmodule
