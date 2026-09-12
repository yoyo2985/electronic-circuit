//------------------------------------------------------------------------------
// tb_mfcc_dump.v  把真实录音 PCM 帧喂给 feature_engine, 并把 RTL 输出逐系数转储
//   输入: data/fe_real.mem  (每行 6 hex, 24bit 有符号 PCM, 共 NF*64 个)
//         data/fe_real_nf.mem(1 行, 帧数 NF)
//   输出: data/fe_real_rtl.txt (每帧一行, 13 个 int16 十进制)
//   与 py/audio_golden.py(整数镜像) 逐位比对用。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_mfcc_dump;

    localparam AW = 24;
    localparam NS = 64;
    localparam K  = 13;
    localparam MAXF = 128;

    reg clk = 1'b0, rst_n = 1'b0;
    reg enable = 1'b0, frame_start = 1'b0, pcm_valid = 1'b0;
    reg signed [AW-1:0] pcm_data = 0;
    wire busy, feature_valid, frame_done;
    wire [3:0] feature_index;
    wire signed [15:0] feature_data;

    feature_engine DUT (
        .clk(clk), .rst_n(rst_n), .enable(enable), .frame_start(frame_start),
        .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .busy(busy), .feature_valid(feature_valid),
        .feature_index(feature_index), .feature_data(feature_data),
        .frame_done(frame_done)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] x[0:MAXF*NS-1];
    reg [15:0]   nfm[0:0];
    wire [15:0]  nf = nfm[0];
    reg signed [15:0] cap[0:MAXF*K-1];
    integer ci, f, n, dcount, fd;

    always @(posedge clk) if (feature_valid) begin
        cap[ci] = feature_data;
        ci = ci + 1;
    end

    always @(posedge clk) if (frame_done) dcount = dcount + 1;

    task feed_frame;
        input integer fr;
        integer m;
        begin
            frame_start = 1'b1;
            @(posedge clk);              // WAIT -> CAPT
            frame_start = 1'b0;
            for (m = 0; m < NS; m = m + 1) begin
                pcm_valid = 1'b1;
                pcm_data  = $signed(x[fr*NS + m]);
                @(posedge clk);
            end
            pcm_valid = 1'b0;
            while (dcount < fr + 1) @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("data/fe_real.mem", x);
        $readmemh("data/fe_real_nf.mem", nfm);
        ci = 0; dcount = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        enable = 1'b1;
        repeat(3) @(posedge clk);

        for (f = 0; f < nf; f = f + 1) feed_frame(f);

        fd = $fopen("data/fe_real_rtl.txt", "w");
        if (fd == 0) begin
            $display("ERROR: cannot open out file");
            $finish;
        end
        for (f = 0; f < nf; f = f + 1) begin
            for (n = 0; n < K; n = n + 1) $fwrite(fd, "%0d ", cap[f*K + n]);
            $fwrite(fd, "\n");
        end
        $fclose(fd);

        $display("DUMP DONE : frames=%0d coefs=%0d", nf, ci);
        $finish;
    end

    initial #500000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
