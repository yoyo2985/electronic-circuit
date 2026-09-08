//------------------------------------------------------------------------------
// tb_utter_vote.v   B5.7 多数投票：7 个极端序列 vs python 镜像
//   N=8 MIN=5。每测喂入后比对 decision 数与最终 owner；测间复位。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_utter_vote;

    localparam NTEST = 7;
    localparam MAXL = 16;

    reg clk = 1'b0, rst_n = 1'b0;
    reg frame_valid = 1'b0, frame_match = 1'b0;
    wire decision_valid;
    wire owner_valid;
    wire [7:0] frames_seen;

    utter_vote #(.VOTE_N(8), .MIN_MATCH(5)) DUT (
        .clk(clk), .rst_n(rst_n), .frame_valid(frame_valid), .frame_match(frame_match),
        .decision_valid(decision_valid), .owner_valid(owner_valid), .frames_seen(frames_seen)
    );

    always #10 clk = ~clk;

    reg uv0[0:15], uv1[0:15], uv2[0:15], uv3[0:15], uv4[0:15], uv5[0:15], uv6[0:15];
    reg selb[0:MAXL-1];
    reg [31:0] flat[0:NTEST*3-1];

    integer t, i, dec, err;

    always @(posedge clk) if (decision_valid) dec = dec + 1;

    task feed_len;
        input integer len;
        integer n;
        begin
            for (n = 0; n < len; n = n + 1) begin
                frame_match = selb[n];
                frame_valid = 1'b1;
                @(posedge clk);
            end
            frame_valid = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("data/uv_0.mem", uv0); $readmemh("data/uv_1.mem", uv1);
        $readmemh("data/uv_2.mem", uv2); $readmemh("data/uv_3.mem", uv3);
        $readmemh("data/uv_4.mem", uv4); $readmemh("data/uv_5.mem", uv5);
        $readmemh("data/uv_6.mem", uv6);
        $readmemh("data/uv_meta.mem", flat);
        err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (t = 0; t < NTEST; t = t + 1) begin
            dec = 0;
            // 选第 t 组序列到 selb
            for (i = 0; i < MAXL; i = i + 1) begin
                case (t)
                    0: selb[i] = uv0[i];
                    1: selb[i] = uv1[i];
                    2: selb[i] = uv2[i];
                    3: selb[i] = uv3[i];
                    4: selb[i] = uv4[i];
                    5: selb[i] = uv5[i];
                    default: selb[i] = uv6[i];
                endcase
            end
            feed_len(flat[3*t]);
            #20;
            if (dec !== flat[3*t+1] || owner_valid !== flat[3*t+2][0]) begin
                if (err < 8)
                    $display("[ERR] test%0d dec=%0d want=%0d owner=%b want=%b",
                             t, dec, flat[3*t+1], owner_valid, flat[3*t+2]);
                err = err + 1;
            end
            // 测间复位
            rst_n = 1'b0; repeat(2) @(posedge clk); rst_n = 1'b1;
        end

        if (err == 0)
            $display("TEST PASS : %0d extreme utterance sequences exact vs python", NTEST);
        else
            $display("TEST FAIL : err=%0d", err);
        $finish;
    end

    initial #500000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
