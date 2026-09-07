//------------------------------------------------------------------------------
// uart_tx.v   UART 发送器（1 起始位 + 8 数据位 LSB 先行 + 1 停止位，无校验）
//   单时钟域：用 BAUD_TICKS 拍产生 1 bit 宽度，不做分频时钟。
//   默认 115200：50MHz/115200 ≈ 434 拍/位。
//   用法：busy==0 时拉高 send 一拍，并给 tx_data，一帧发完自动回 IDLE。
//   空闲电平为高(tx=1)。
// 参数化：BAUD_TICKS（每 bit 的时钟数，仿真改小如 8）。
// 复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module uart_tx #(
    parameter BAUD_TICKS = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       send,       // 请求发送（一拍脉冲）
    input  wire [7:0] tx_data,    // 待发字节（LSB 先）
    output reg        tx,         // 串行输出（空闲高）
    output reg        busy        // 1=正在发送
);
    localparam B_W = $clog2(BAUD_TICKS);

    localparam ST_IDLE = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA = 2'd2;
    localparam ST_STOP = 2'd3;

    reg [1:0]  state;
    reg [2:0]  bitidx;          // 当前数据位 0..7
    reg [B_W-1:0] cnt;          // bit 内倒计时
    reg [7:0]  shreg;           // 待发位缓冲

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= ST_IDLE;
            tx     <= 1'b1;
            busy   <= 1'b0;
            bitidx <= 3'd0;
            cnt    <= {B_W{1'b0}};
            shreg  <= 8'h00;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (send) begin                 // 装载并进入起始位
                        busy   <= 1'b1;
                        tx     <= 1'b0;
                        shreg  <= tx_data;
                        cnt    <= BAUD_TICKS - 1;
                        state  <= ST_START;
                    end
                end
                ST_START: begin                     // 起始位(低)持续 BAUD_TICKS 拍
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin
                        cnt    <= BAUD_TICKS - 1;
                        tx     <= shreg[0];         // 进入第 0 位
                        bitidx <= 3'd0;
                        state  <= ST_DATA;
                    end
                end
                ST_DATA: begin                      // 8 位数据，LSB 先行
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin
                        cnt <= BAUD_TICKS - 1;
                        if (bitidx == 3'd7) begin
                            tx    <= 1'b1;          // 数据发完 -> 停止位
                            state <= ST_STOP;
                        end else begin
                            bitidx <= bitidx + 1'b1;
                            tx     <= shreg[1];     // 输出下一位
                            shreg  <= {1'b0, shreg[7:1]};
                        end
                    end
                end
                ST_STOP: begin                      // 停止位(高)
                    cnt <= cnt - 1'b1;
                    if (cnt == {B_W{1'b0}}) begin
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
