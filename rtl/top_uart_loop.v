//------------------------------------------------------------------------------
// top_uart_loop.v  06+07 UART 自发自收 loopback 演示（顶层）
//   自产自销：周期性把 ASCII '0'..'9' 从 TXD 发出；把 TXD 与 RXD 短接后，
//   uart_rx 收回自己发的字节，解码出数字显示在数码管最右位，LED3..0 回显。
//   若短接正常，数码管与 LED 会同步循环 0~9（RX 落后 TX 一帧）。
//   短接：TXD(D12) ──导线── RXD(F12)（两脚都在扩展排针上）。
//   波特率默认 115200。SW0(A9)=rst_n 拨上=运行。
// 参数化：MS_DIV / BAUD_TICKS / GAP_MS。
//------------------------------------------------------------------------------
module top_uart_loop #(
    parameter MS_DIV    = 50000,
    parameter BAUD_TICKS = 434,
    parameter GAP_MS    = 200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,        // RXD = F12
    output wire       tx,        // TXD = D12
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    // ---- 发送控制器：每个 GAP_MS 发一个 '0'..'9'，循环 ----
    reg [3:0] digit;
    reg [15:0] wait_ms;
    reg        sending;
    reg        send;
    reg        busy_d1;
    wire       tx_busy;
    wire       busy_fell = busy_d1 & ~tx_busy;

    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(8'd48 + digit),
        .tx(tx), .busy(tx_busy)
    );

    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            digit   <= 4'd0;
            wait_ms <= 16'd0;
            sending <= 1'b0;
            busy_d1 <= 1'b0;
        end else begin
            busy_d1 <= tx_busy;
            if (busy_fell) sending <= 1'b0;
            if (!sending) begin
                if (wait_ms >= GAP_MS) begin
                    wait_ms <= 16'd0;
                    sending <= 1'b1;
                    send    <= 1'b1;
                    if (digit == 4'd9) digit <= 4'd0;
                    else               digit <= digit + 4'd1;
                end else if (tick_1ms) begin
                    wait_ms <= wait_ms + 16'd1;
                end
            end
        end
    end

    // ---- 接收：RXD 收回的字节，若是 '0'..'9' 转成数字显示 ----
    wire rx_done;
    wire [7:0] rx_byte;
    uart_rx #(.BAUD_TICKS(BAUD_TICKS)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(rx),
        .rx_done(rx_done), .rx_data(rx_byte), .rx_busy()
    );

    reg [3:0] show;
    reg       show_valid;
    always @(posedge clk) begin
        if (!rst_n) begin
            show       <= 4'd0;
            show_valid <= 1'b0;
        end else if (rx_done) begin
            if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                show       <= rx_byte - 8'h30;   // '0'..'9' -> 0..9
                show_valid <= 1'b1;
            end else
                show_valid <= 1'b0;
        end
    end

    wire [3:0] blank = show_valid ? 4'b1110 : 4'b1111;   // 只显示最右一位
    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({12'd0, show}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    assign led = {4'b0000, show};
endmodule
