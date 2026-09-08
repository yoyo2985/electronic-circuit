//------------------------------------------------------------------------------
// tb_speaker_verify.v   B5.3 feature_engine→vtmpl 端到端（3 帧）
//   帧序: sine(owner,期望 match=1)/zero/rand。期望 data/spk_exp.mem
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_speaker_verify;

    localparam AW = 24;
    localparam NS = 64;
    localparam NF = 3;

    reg clk = 1'b0, rst_n = 1'b0;
    reg enable = 1'b0, frame_start = 1'b0, pcm_valid = 1'b0;
    reg signed [AW-1:0] pcm_data = 0;

    wire fe_valid;
    wire [3:0] fe_idx;
    wire signed [15:0] fe_data;
    wire fe_done;
    wire fe_busy;

    wire sv_frame;
    wire [31:0] sv_dist;
    wire sv_match;
    wire owner;

    feature_engine DUT_fe (
        .clk(clk), .rst_n(rst_n), .enable(enable), .frame_start(frame_start),
        .pcm_valid(pcm_valid), .pcm_data(pcm_data),
        .busy(fe_busy), .feature_valid(fe_valid),
        .feature_index(fe_idx), .feature_data(fe_data), .frame_done(fe_done)
    );

    speaker_verify DUT_sv (
        .clk(clk), .rst_n(rst_n),
        .fe_feature_valid(fe_valid), .fe_index(fe_idx), .fe_feature_data(fe_data),
        .frame_valid(sv_frame), .frame_dist(sv_dist), .frame_match(sv_match),
        .owner_valid(owner)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] p0[0:NS-1], p1[0:NS-1], p2[0:NS-1];
    reg [31:0] flat[0:NF*2-1];
    integer i, res, err;
    reg [AW-1:0] pb[0:NS-1];

    always @(posedge clk) begin
        if (sv_frame) begin
            if (res < NF) begin
                if (sv_dist !== flat[2*res] || sv_match !== flat[2*res+1][0]) begin
                    if (err < 8)
                        $display("[ERR] f%0d dist=%0d want=%0d match=%b want=%b",
                                 res, sv_dist, flat[2*res], sv_match, flat[2*res+1]);
                    err = err + 1;
                end
            end
            res = res + 1;
        end
    end

    task feed_pb;
        input integer want;
        integer n;
        begin
            frame_start = 1'b1;
            @(posedge clk);
            frame_start = 1'b0;
            for (n = 0; n < NS; n = n + 1) begin
                pcm_valid = 1'b1;
                pcm_data  = $signed(pb[n]);
                @(posedge clk);
            end
            pcm_valid = 1'b0;
            while (res < want) @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("data/fe_sine.mem", p0);
        $readmemh("data/fe_zero.mem", p1);
        $readmemh("data/fe_rand.mem", p2);
        $readmemh("data/spk_exp.mem", flat);
        res = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        enable = 1'b1;
        repeat(3) @(posedge clk);

        for (i = 0; i < NS; i = i + 1) pb[i] = p0[i];
        feed_pb(1);
        for (i = 0; i < NS; i = i + 1) pb[i] = p1[i];
        feed_pb(2);
        for (i = 0; i < NS; i = i + 1) pb[i] = p2[i];
        feed_pb(3);

        #100;
        if (err == 0 && res == NF)
            $display("TEST PASS : %0d speaker frames dist/match exact", res);
        else
            $display("TEST FAIL : res=%0d err=%0d", res, err);
        $finish;
    end

    initial #30000000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
