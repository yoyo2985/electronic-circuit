//------------------------------------------------------------------------------
// voice_cap_rpt.v  Phase5a 板上真值采集：每段语音(VAD rise→fall)累加各 MFCC 维之和
//   与帧数，段结束后经 UART 发一行固定长 ASCII(供 PC 收 → Python 求均值重建模板)：
//     行格式(114 字节): 'M' + 14 个 8-hex 字段(各占 8 字节, 无分隔):
//       字段0 = 帧数 count, 字段1..13 = dim0..12 的 int32 和(2 补码 hex8)
//     PC 侧: 每维均值 = round(sum / count) → int16，即 build_speaker_template 口径。
//   计的是"VAD 期间由 v2_frame_ctrl 实际送出的帧"(仅语音帧)。段起始复位累加器。
//   复位：同步低有效 rst_n(建议接 audio_rst_n)。内部例化 uart_tx(115200)。
//------------------------------------------------------------------------------
module voice_cap_rpt #(
    parameter BAUD_TICKS = 434,
    parameter N_DIM      = 13
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       fe_valid,       // feature_engine.feature_valid
    input  wire [3:0] fe_index,       // 0..12
    input  wire signed [15:0] fe_data,
    input  wire       vad,            // audio_vad.vad
    input  wire       vad_rise,       // audio_vad.vad_rise
    input  wire       vad_fall,       // audio_vad.vad_fall
    output wire       tx
);
    integer k;
    reg signed [31:0] sum[0:N_DIM-1];
    reg [31:0]        cnt;
    reg [31:0]        cnt_s;
    reg signed [31:0] sum_s[0:N_DIM-1];

    // ---------- 段内累加: 复位于 rst 或新段开始; 每帧(idx==0)计一帧; 每个系数累加 ----------
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 32'd0;
            for (k = 0; k < N_DIM; k = k + 1) sum[k] <= 32'sd0;
        end else begin
            if (vad_rise) begin
                cnt <= 32'd0;
                for (k = 0; k < N_DIM; k = k + 1) sum[k] <= 32'sd0;
            end
            if (fe_valid && vad) begin
                if (fe_index == 4'd0) cnt <= cnt + 32'd1;
                sum[fe_index[3:0]] <= sum[fe_index[3:0]] + fe_data;
            end
        end
    end

    // ---------- 段结束锁存 + 发送请求 ----------
    reg start_send;
    reg [1:0] sst;                    // 0=idle 1=in_seg 2=pend_send
    always @(posedge clk) begin
        if (!rst_n) begin sst <= 2'd0; start_send <= 1'b0; end
        else begin
            start_send <= 1'b0;
            case (sst)
                2'd0: if (vad) sst <= 2'd1;
                2'd1: if (vad_fall) begin
                          sst <= 2'd2;
                          cnt_s <= cnt;
                          for (k = 0; k < N_DIM; k = k + 1) sum_s[k] <= sum[k];
                          start_send <= 1'b1;
                      end else if (!vad) sst <= 2'd0;
                2'd2: if (!vad) sst <= 2'd0;   // 段彻底结束后下一次再采集
            endcase
        end
    end

    // ---------- uart_tx ----------
    wire tx_busy;
    reg send;
    reg [7:0] byte_out;
    uart_tx #(.BAUD_TICKS(BAUD_TICKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(tx_busy)
    );

    localparam NBYTES = 114;          // 'M' + 8*14 + '\n'
    function [7:0] hexc(input [3:0] n);
        hexc = (n < 4'd10) ? (8'h30 + n) : (8'h37 + n);
    endfunction
    function [3:0] digit8(input [31:0] v, input [2:0] d);
        digit8 = v[(3'd7 - d) * 4 +: 4];
    endfunction

    reg [6:0] bi;                     // 0..113
    reg [3:0] nib;
    reg [7:0] cb;
    always @(*) begin
        if (bi == 7'd0) cb = "M";
        else if (bi == NBYTES - 1) cb = "\n";
        else begin
            nib = 4'd0;
            case ((bi - 7'd1) / 8)
                4'd0:  nib = digit8(cnt_s,  (bi - 7'd1) % 8);
                4'd1:  nib = digit8(sum_s[0],  (bi - 7'd1) % 8);
                4'd2:  nib = digit8(sum_s[1],  (bi - 7'd1) % 8);
                4'd3:  nib = digit8(sum_s[2],  (bi - 7'd1) % 8);
                4'd4:  nib = digit8(sum_s[3],  (bi - 7'd1) % 8);
                4'd5:  nib = digit8(sum_s[4],  (bi - 7'd1) % 8);
                4'd6:  nib = digit8(sum_s[5],  (bi - 7'd1) % 8);
                4'd7:  nib = digit8(sum_s[6],  (bi - 7'd1) % 8);
                4'd8:  nib = digit8(sum_s[7],  (bi - 7'd1) % 8);
                4'd9:  nib = digit8(sum_s[8],  (bi - 7'd1) % 8);
                4'd10: nib = digit8(sum_s[9],  (bi - 7'd1) % 8);
                4'd11: nib = digit8(sum_s[10], (bi - 7'd1) % 8);
                4'd12: nib = digit8(sum_s[11], (bi - 7'd1) % 8);
                default: nib = digit8(sum_s[12], (bi - 7'd1) % 8);
            endcase
            cb = hexc(nib);
        end
    end
    always @(posedge clk) byte_out <= cb;

    reg framing, sent;
    always @(posedge clk) begin
        send <= 1'b0;
        if (!rst_n) begin framing <= 0; sent <= 0; bi <= 0; end
        else begin
            if (!framing) begin
                sent <= 1'b0;
                if (start_send) begin framing <= 1'b1; bi <= 7'd0; end
            end else if (!sent) begin
                if (!tx_busy) begin send <= 1'b1; sent <= 1'b1; end
            end else begin
                if (!tx_busy) begin
                    sent <= 1'b0;
                    if (bi == NBYTES - 1) framing <= 1'b0;
                    else bi <= bi + 7'd1;
                end
            end
        end
    end
endmodule
