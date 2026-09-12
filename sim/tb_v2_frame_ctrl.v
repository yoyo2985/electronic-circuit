`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_v2_frame_ctrl.v  语音帧控制器 → feature_engine 连续出帧验证
//   合成 48k 采样节拍 + 变化 PCM(三角波)；speech 拉高一段时间 → 控制器应喂出连续
//   64 采样/帧，引擎每帧产出 13 个 MFCC(feature_valid×13) 与 frame_done。
//   断言：frames_sent ≥ 期望帧数、feature_valid 脉冲数 ≈ 13×帧数、frame_done 数。
//   注意：必须在 sim/audio_sim 目录跑(引擎系数表 $readmemh "data/*.mem")。
//------------------------------------------------------------------------------
module tb_v2_frame_ctrl;
    localparam SAMP_PER = 100;          // 每 100 clk 一个采样(≈加速)
    reg clk = 0;
    always #10 clk = ~clk;

    reg rst_n = 0;
    reg sample_ok = 0;
    reg speech = 0;
    reg signed [23:0] pcm = 24'sd0;
    integer sck = 0;
    reg [31:0] n_samp = 0;

    wire frame_start, fe_pcm_valid;
    wire signed [23:0] fe_pcm;
    wire fe_busy, fe_valid, fe_done;
    wire [3:0] fe_index;
    wire signed [15:0] fe_data;
    wire [31:0] frames_sent;

    v2_frame_ctrl u_ctrl (
        .clk(clk), .rst_n(rst_n), .sample_ok(sample_ok), .pcm_l(pcm),
        .speech(speech), .fe_busy(fe_busy),
        .frame_start(frame_start), .fe_pcm_valid(fe_pcm_valid), .fe_pcm(fe_pcm),
        .frames_sent(frames_sent)
    );
    feature_engine u_fe (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .frame_start(frame_start), .pcm_valid(fe_pcm_valid), .pcm_data(fe_pcm),
        .busy(fe_busy), .feature_valid(fe_valid), .feature_index(fe_index),
        .feature_data(fe_data), .frame_done(fe_done)
    );

    // 采样节拍 + 三角波 PCM
    always @(posedge clk) begin
        sample_ok <= 1'b0;
        if (!rst_n) begin sck <= 0; n_samp <= 0; end
        else begin
            if (sck == SAMP_PER - 1) begin
                sck <= 0; sample_ok <= 1'b1; n_samp <= n_samp + 1;
            end else sck <= sck + 1;
        end
        if (sample_ok)
            pcm <= $signed({ {8{n_samp[7]}}, n_samp[7:0] }) * 32'sd1024;
    end

    integer fev, fdone;
    always @(posedge clk) begin
        if (!rst_n) begin fev <= 0; fdone <= 0; end
        else begin
            if (fe_valid) fev <= fev + 1;
            if (fe_done)  fdone <= fdone + 1;
        end
    end

    integer err;
    integer i;
    initial begin
        err = 0;
        $display("=== tb_v2_frame_ctrl start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (2000) @(posedge clk);

        // 说话 5000 个采样(≈78 帧窗口)
        speech = 1;
        i = 0;
        while (frames_sent < 60 && i < 2000000) begin @(posedge clk); i = i + 1; end
        speech = 0;
        // 等引擎把已开帧收尾
        repeat (20000) @(posedge clk);

        $display("frames_sent=%0d  feature_valid=%0d frame_done=%0d",
                 frames_sent, fev, fdone);
        if (frames_sent < 55) begin $display("FAIL: 帧数不足(期望≥55)"); err = err + 1; end
        if (fdone < 50)       begin $display("FAIL: frame_done 不足"); err = err + 1; end
        if (fev < 13 * 50)    begin $display("FAIL: MFCC 系数不足(期望≈13×帧)"); err = err + 1; end
        if (err == 0) $display("=== tb_v2_frame_ctrl PASS ===");
        else          $display("=== tb_v2_frame_ctrl FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
