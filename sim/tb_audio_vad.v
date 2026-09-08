//------------------------------------------------------------------------------
// tb_audio_vad.v   验证 VAD 滞回+拖尾：
//   帧序列（F_LEN=8 采样/帧，每采样 S=8 clk）：
//     静音×3 → 语音×6 → 静音×8 → 语音×4 → 静音×20
//   期望：vad 语音段高、静音内保持 HO_FRAMES=4 帧才掉；rise 2 次 / fall 2 次，
//         结束时 vad==0。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_audio_vad;

    localparam AW = 24;
    localparam S  = 8;                // 采样间隔(clk)
    localparam F  = 8;                // 每帧采样数(与 DUT F_LEN_LOG2=3 对应)
    localparam FRAMES = 45;           // 总帧数
    localparam NSAMP  = FRAMES * F;

    reg clk = 1'b0, rst_n = 1'b0;
    reg sample_ok = 1'b0;
    reg [AW-1:0] pcm_l = 0, pcm_r = 0;
    wire vad, vad_rise, vad_fall;
    wire [AW:0] peak;

    audio_vad #(
        .AW(AW), .F_LEN_LOG2(3),
        .TH_ON(24'h4000), .TH_OFF(24'h1000), .HO_FRAMES(4)
    ) DUT (
        .clk(clk), .rst_n(rst_n), .sample_ok(sample_ok),
        .pcm_l(pcm_l), .pcm_r(pcm_r),
        .vad(vad), .vad_rise(vad_rise), .vad_fall(vad_fall), .peak(peak)
    );

    always #10 clk = ~clk;

    // 每帧幅度：静音=0x400，语音=0x8000
    function [AW-1:0] famp(input [31:0] f);
        begin
            if ((f >= 3 && f <= 8) || (f >= 17 && f <= 20)) famp = 24'h8000;
            else famp = 24'h400;
        end
    endfunction

    // 生成 sample_ok + pcm（每采样符号交替，测试 |x| 峰值正确）
    reg [3:0]  sdiv;
    reg [31:0] s;
    reg [AW-1:0] ma;
    always @(posedge clk) begin
        if (!rst_n) begin
            sample_ok <= 1'b0; sdiv <= 0; s <= 0; pcm_l <= 0; pcm_r <= 0;
        end else begin
            sample_ok <= 1'b0;
            if (sdiv == S - 1) begin
                sdiv <= 0;
                s <= s + 1;
                sample_ok <= 1'b1;
                ma = famp(s / F);
                pcm_l <= (s[0] ? ~ma + 1'b1 : ma);   // 交替正负
                pcm_r <= (s[1] ? ~ma + 1'b1 : ma);
            end else begin
                sdiv <= sdiv + 1'b1;
            end
        end
    end

    // 事件计数 + 采样计数
    reg [31:0] sc;
    integer rc = 0, fc = 0;
    always @(posedge clk) begin
        if (!rst_n) begin sc <= 0; rc <= 0; fc <= 0; end
        else begin
            if (sample_ok) sc <= sc + 1;
            if (vad_rise)  rc <= rc + 1;
            if (vad_fall)  fc <= fc + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat(8) @(posedge clk);
        rst_n = 1'b1;

        wait (sc >= NSAMP);            // 播完整段
        #60;

        if (rc == 2 && fc == 2 && vad == 1'b0)
            $display("TEST PASS : rise=%0d fall=%0d final_vad=0 peak=%0h", rc, fc, peak);
        else
            $display("TEST FAIL : rise=%0d fall=%0d vad=%b peak=%0h", rc, fc, vad, peak);
        $finish;
    end

    initial #400000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
