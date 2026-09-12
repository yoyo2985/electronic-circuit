//------------------------------------------------------------------------------
// dir_energy.v  双麦能量方向感知(FPGA 极简方案, 无 NN/TDOA)
//   VAD 段内逐采样累加左右声道幅度: SL=Σ|pcm_l|, SR=Σ|pcm_r|(仅静音外的语音段)。
//   段末(vad_fall)按比例判向(尺度无关, 不用除法):
//     SL·DEN > SR·NUM  → LEFT ; SR·DEN > SL·NUM → RIGHT ; 否则 CENTER
//   默认 NUM=5/DEN=4 即能量比 >1.25× 才算偏侧。
//   输出 dir 段末锁存(0=中 1=左 2=右), dir_valid 段末单拍脉冲。
//   硬件前提: 模块双麦 L/R 已各接一颗咪头, 声道独立(2026-09-09 A1 捂麦验证)。
//------------------------------------------------------------------------------
module dir_energy #(
    parameter AW  = 24,
    parameter NUM = 5,           // 偏侧判据分子
    parameter DEN = 4            // 偏侧判据分母
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            sample_ok,     // 每个立体声对 1 拍(48k)
    input  wire [AW-1:0]   pcm_l,
    input  wire [AW-1:0]   pcm_r,
    input  wire            vad,
    input  wire            vad_rise,
    input  wire            vad_fall,
    output reg  [1:0]      dir,           // 0=中 1=左 2=右
    output reg             dir_valid      // 段末脉冲
);
    reg  [47:0] sum_l, sum_r;
    wire signed [AW-1:0] sl = pcm_l;
    wire signed [AW-1:0] sr = pcm_r;
    wire [AW-1:0] mag_l = sl[AW-1] ? (~sl + 1'b1) : sl;
    wire [AW-1:0] mag_r = sr[AW-1] ? (~sr + 1'b1) : sr;

    always @(posedge clk) begin
        if (!rst_n) begin
            sum_l <= 48'd0; sum_r <= 48'd0; dir <= 2'd0; dir_valid <= 1'b0;
        end else begin
            dir_valid <= 1'b0;
            if (vad_rise) begin sum_l <= 48'd0; sum_r <= 48'd0; end
            if (sample_ok && vad) begin
                sum_l <= sum_l + mag_l;
                sum_r <= sum_r + mag_r;
            end
            if (vad_fall) begin
                if (sum_l * DEN > sum_r * NUM)      dir <= 2'd1;   // 左
                else if (sum_r * DEN > sum_l * NUM) dir <= 2'd2;   // 右
                else                                dir <= 2'd0;   // 中
                dir_valid <= 1'b1;
            end
        end
    end
endmodule
