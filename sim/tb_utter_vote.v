//------------------------------------------------------------------------------
// tb_utter_vote.v   B5.7c 段级累计投票：7 个极端段 vs python 镜像
//   MIN_MATCH=5。段内(vad=1)逐帧喂 seq；vad 落下段末出 decision 脉冲。
//   比对: 段内粘性 owner_valid 与段末 decision 数与 python 镜像一致。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_utter_vote;

    localparam NTEST = 7;
    localparam MAXL = 16;

    reg clk = 1'b0, rst_n = 1'b0;
    reg vad = 1'b0, frame_valid = 1'b0, frame_match = 1'b0;
    wire decision_valid;
    wire owner_valid;
    wire [7:0] frames_seen;

    utter_vote #(.MIN_MATCH(5)) DUT (
        .clk(clk), .rst_n(rst_n), .vad(vad),
        .frame_valid(frame_valid), .frame_match(frame_match),
        .decision_valid(decision_valid), .owner_valid(owner_valid), .frames_seen(frames_seen)
    );

    always #10 clk = ~clk;

    reg uv0[0:15], uv1[0:15], uv2[0:15], uv3[0:15], uv4[0:15], uv5[0:15], uv6[0:15];
    reg selb[0:MAXL-1];
    reg [31:0] flat[0:NTEST*3-1];

    integer t, i, err, owner_during, decv_during;

    task feed_len;
        input integer len;
        integer n;
        begin
            vad = 1'b1;
            for (n = 0; n < len; n = n + 1) begin
                frame_match = selb[n];
                frame_valid = 1'b1;
                @(posedge clk);
            end
            frame_valid = 1'b0;
            @(posedge clk);                 // 段内最后一拍(NBA 已生效)
            #1;
            owner_during = owner_valid;     // 段内粘性 owner
            vad = 1'b0;                     // 段末
            @(posedge clk);                 // 段末边沿: decision_valid <= owner
            #1;
            decv_during = decision_valid;   // 本段判决
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
            if (owner_during !== flat[3*t+2][0] || decv_during !== flat[3*t+2][0]) begin
                if (err < 8)
                    $display("[ERR] test%0d owner=%b want=%b decv=%b want=%b",
                             t, owner_during, flat[3*t+2], decv_during, flat[3*t+2]);
                err = err + 1;
            end
            // 测间复位
            rst_n = 1'b0; repeat(2) @(posedge clk); rst_n = 1'b1;
        end

        if (err == 0)
            $display("TEST PASS : %0d extreme utterance segments exact vs python", NTEST);
        else
            $display("TEST FAIL : err=%0d", err);
        $finish;
    end

    initial #500000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
