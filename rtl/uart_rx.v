//------------------------------------------------------------------------------
// uart_rx.v    UART 接收器（1 起始位 + 8 数据位 LSB 先行 + 1 停止位）
//   空闲为高。检测到起始位下沿后，在每位中心采样：
//     起始下沿 → 等半位到起始中心 → 每 BAUD_TICKS 拍采 1 个数据位(中心)，
//     采 8 位后到停止位，校验位不做。接收完给出 rx_done 一拍脉冲。
//   起始中心若已回高(毛刺/误触发)则回 IDLE 丢弃(伪起始拒收)。
//   单时钟域，不做分频时钟。默认 115200：BAUD_TICKS=434。
// 参数化：BAUD_TICKS（每 bit 时钟数，仿真改小如 8）。
// 复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module uart_rx #(
    parameter BAUD_TICKS = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,         // 串行输入（空闲高）
    output reg        rx_done,    // 一字节接收完成脉冲（1 拍）
    output reg  [7:0] rx_data,    // 收到的字节
    output reg        rx_busy     // 1=正在接收
);
    localparam B_W = $clog2(BAUD_TICKS);

    localparam ST_IDLE  = 2'd0;
    localparam ST_HALF  = 2'd1;   // 等起始位中心
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  st;
    reg [B_W-1:0] cnt;
    reg [2:0]  bitidx;
    reg [7:0]  shift;

    // 输入同步（两级 FF）
    reg r1, r2;
    always @(posedge clk) begin
        if (!rst_n) begin r1 <= 1'b1; r2 <= 1'b1; end
        else begin r1 <= rx; r2 <= r1; end
    end

    always @(posedge clk) begin
        rx_done <= 1'b0;
        if (!rst_n) begin
            st     <= ST_IDLE;
            cnt    <= {B_W{1'b0}};
            bitidx <= 3'd0;
            shift  <= 8'h00;
            rx_data<= 8'h00;
            rx_busy<= 1'b0;
        end else begin
            case (st)
                ST_IDLE: begin
                    rx_busy <= 1'b0;
                    if (!r2) begin                     // 检测到起始位下沿
                        rx_busy <= 1'b1;
                        st      <= ST_HALF;
                        cnt     <= (BAUD_TICKS >> 1) - 1;  // 到起始中心
                    end
                end
                ST_HALF: begin
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin
                        if (r2) begin                  // 中心已回高 → 伪起始，丢弃
                            st      <= ST_IDLE;
                            rx_busy <= 1'b0;
                        end else begin
                            st      <= ST_DATA;
                            bitidx  <= 3'd0;
                            cnt     <= BAUD_TICKS - 1; // 距第 0 位中心一整个位宽
                        end
                    end
                end
                ST_DATA: begin
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin      // 到某位中心
                        shift[bitidx] <= r2;           // LSB 先行：bit k 存到第 k 位
                        if (bitidx == 3'd7) begin
                            st  <= ST_STOP;
                            cnt <= BAUD_TICKS - 1;
                        end else begin
                            bitidx <= bitidx + 1'b1;
                            cnt    <= BAUD_TICKS - 1;
                        end
                    end
                end
                ST_STOP: begin
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin
                        rx_data <= shift;
                        rx_done <= 1'b1;
                        st      <= ST_IDLE;
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
