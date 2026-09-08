//------------------------------------------------------------------------------
// telemetry_voice.v   语音链遥测帧（在原格式上扩展）
//   帧: [AA][ctl][tgt][pos][chk]，共 5 字节；ctl={owner_valid, cmd_id[1:0], act[2:0]}
//   复用 uart_tx(busy 握手)。每 TELEM_MS 发一帧。不改原 uart_telemetry。
//------------------------------------------------------------------------------
module telemetry_voice #(
    parameter TELEM_MS = 100,
    parameter BAUD_TICKS = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,
    input  wire       owner,
    input  wire [1:0] cmd_id,
    input  wire [2:0] action,
    input  wire [9:0] target,
    input  wire [9:0] pos,
    output wire       tx
);
    wire busy;
    reg send;
    reg [7:0] byte_out;
    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(busy));

    reg [15:0] ms;
    reg [2:0]  bi;
    reg        framing, sent;

    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin
            ms <= 0; bi <= 0; framing <= 1'b0; sent <= 1'b0; byte_out <= 0;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (tick_1ms) begin
                    if (ms >= TELEM_MS - 1) begin ms <= 0; framing <= 1'b1; bi <= 0; end
                    else ms <= ms + 1;
                end
            end else if (!sent) begin
                if (!busy) begin
                    case (bi)
                        0: byte_out <= 8'hAA;
                        1: byte_out <= {owner, cmd_id, action};   // 新字段
                        2: byte_out <= target[7:0];
                        3: byte_out <= pos[7:0];
                        default: byte_out <= 8'hAA ^ {owner, cmd_id, action}
                                       ^ target[7:0] ^ pos[7:0];
                    endcase
                    send <= 1'b1; sent <= 1'b1;
                end
            end else begin
                if (!busy) begin
                    sent <= 1'b0;
                    if (bi == 4) framing <= 1'b0; else bi <= bi + 1;
                end
            end
        end
    end
endmodule
