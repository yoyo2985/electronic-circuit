//------------------------------------------------------------------------------
// tb_feature_engine.v   B4 帧级特征引擎比对（3 组：全0 / 1kHz / 定种子随机）
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_feature_engine;

    localparam AW = 24;
    localparam NS = 64;
    localparam K  = 13;

    reg clk = 1'b0, rst_n = 1'b0;
    reg enable = 1'b0, frame_start = 1'b0, pcm_valid = 1'b0;
    reg signed [AW-1:0] pcm_data = 0;
    wire busy;
    wire feature_valid;
    wire [3:0] feature_index;
    wire signed [15:0] feature_data;
    wire frame_done;

    feature_engine DUT (
        .clk(clk), .rst_n(rst_n), .enable(enable), .frame_start(frame_start),
        .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .busy(busy), .feature_valid(feature_valid),
        .feature_index(feature_index), .feature_data(feature_data),
        .frame_done(frame_done)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] pb[0:NS-1];       // 待喂缓冲
    reg [15:0]   e0[0:K-1], e1[0:K-1], e2[0:K-1];
    reg [AW-1:0] x0[0:NS-1], x1[0:NS-1], x2[0:NS-1];

    integer fcnt, dcount, err;

    always @(posedge clk) begin
        if (feature_valid) begin
            case (fcnt / K)
                0: if (feature_data !== $signed(e0[feature_index])) err = err + 1;
                1: if (feature_data !== $signed(e1[feature_index])) err = err + 1;
                2: if (feature_data !== $signed(e2[feature_index])) err = err + 1;
                default: err = err + 1;
            endcase
            fcnt = fcnt + 1;
        end
        if (frame_done) dcount = dcount + 1;
    end

    task feed_pb;
        input integer want_done;     // 等 dcount 到此
        integer n;
        begin
            frame_start = 1'b1;
            @(posedge clk);          // WAIT→CAPT
            frame_start = 1'b0;
            for (n = 0; n < NS; n = n + 1) begin
                pcm_valid = 1'b1;
                pcm_data  = $signed(pb[n]);
                @(posedge clk);
            end
            pcm_valid = 1'b0;
            while (dcount < want_done) @(posedge clk);
        end
    endtask

    integer i;
    initial begin
        $readmemh("data/fe_zero.mem", x0);
        $readmemh("data/fe_zero_mfcc.mem", e0);
        $readmemh("data/fe_sine.mem", x1);
        $readmemh("data/fe_sine_mfcc.mem", e1);
        $readmemh("data/fe_rand.mem", x2);
        $readmemh("data/fe_rand_mfcc.mem", e2);
        fcnt = 0; dcount = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        enable = 1'b1;
        repeat(3) @(posedge clk);

        for (i = 0; i < NS; i = i + 1) pb[i] = x0[i];
        feed_pb(1);
        for (i = 0; i < NS; i = i + 1) pb[i] = x1[i];
        feed_pb(2);
        for (i = 0; i < NS; i = i + 1) pb[i] = x2[i];
        feed_pb(3);

        #100;
        if (err == 0 && fcnt == 3 * K)
            $display("TEST PASS : %0d features, 3 frames, all exact", fcnt);
        else
            $display("TEST FAIL : fcnt=%0d dcount=%0d err=%0d", fcnt, dcount, err);
        $finish;
    end

    initial #50000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
