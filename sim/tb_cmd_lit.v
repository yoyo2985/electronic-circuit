//------------------------------------------------------------------------------
// tb_cmd_lit.v   校验 cmd_matcher 模板参数内嵌常量 == data/commands/*.mem 真值
//   对 4 个命令模板依次喂 13 维原样向量:
//     dist 应≈0(证明字面量与 mem 逐维一致), argmin 应==自身索引(0停/1左/2右/3前)。
//   $readmemh 仅用于仿真对照 —— TD 综合端不受影响(模板在 cmd_matcher 参数内)。
//   失败以 $display FAIL / 最终 $finish 退出码返回。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_cmd_lit;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [15:0] in_v = 0;
    wire cmdv;
    wire [1:0] cmdid;
    wire [31:0] dist;

    reg signed [15:0] t0 [0:12], t1 [0:12], t2 [0:12], t3 [0:12];

    initial begin
        $readmemh("../../data/commands/cmd_stop.mem",    t0);
        $readmemh("../../data/commands/cmd_left.mem",    t1);
        $readmemh("../../data/commands/cmd_right.mem",   t2);
        $readmemh("../../data/commands/cmd_forward.mem", t3);
    end

    cmd_matcher u_cmd (
        .clk(clk), .rst_n(rst_n),
        .mfcc_valid(in_valid), .mfcc_data(in_v),
        .cmd_valid(cmdv), .cmd_id(cmdid), .cmd_dist_min(dist)
    );

    always #5 clk = ~clk;

    integer fails = 0;

    task feed_vec;
        input [1:0] which;
        integer d;
        begin
            for (d = 0; d <= 12; d = d + 1) begin
                @(posedge clk);
                in_valid = 1'b1;
                case (which)
                    0: in_v = t0[d];
                    1: in_v = t1[d];
                    2: in_v = t2[d];
                    default: in_v = t3[d];
                endcase
            end
            @(posedge clk);
            in_valid = 1'b0;
            in_v = 0;
            // cmd_matcher: vtmpl out_valid(第13拍) -> pending -> 下一拍出结果
            wait (cmdv === 1'b1);
            #1;
            if (dist > 32'd4) begin
                $display("FAIL which=%0d dist=%0d (期望≈0)", which, dist);
                fails = fails + 1;
            end
            if (cmdid !== which) begin
                $display("FAIL which=%0d cmd_id=%0d (期望=%0d)", which, cmdid, which);
                fails = fails + 1;
            end else begin
                $display("PASS 模板%0d: dist=%0d cmd_id=%0d", which, dist, cmdid);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        #20;
        rst_n = 1'b1;
        @(posedge clk);
        feed_vec(0);
        feed_vec(1);
        feed_vec(2);
        feed_vec(3);
        if (fails == 0) $display("ALL 4 TEMPLATES PASS");
        else            $display("FAILS=%0d", fails);
        $finish;
    end

endmodule
