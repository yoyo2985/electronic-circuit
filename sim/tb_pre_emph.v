//------------------------------------------------------------------------------
// tb_pre_emph.v   B3-1 定点预加重逐点 Golden 比对
//   输入/期望向量由 python py/gen_preemph_vec.py 生成到 data/pre_in.mem、pre_exp.mem。
//   运行目录：sim/audio_sim。期望输出与 RTL 完全逐位一致 → 全 PASS。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_pre_emph;

    localparam AW = 24;
    localparam LEN = 700;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [AW-1:0] x = 0;
    wire out_valid;
    wire signed [AW-1:0] y;

    pre_emph #(.AW(AW), .Q(14), .A_FIX(15892)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .x(x),
        .out_valid(out_valid), .y(y)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] xin[0:LEN-1];
    reg [AW-1:0] exp[0:LEN-1];

    integer i, oc, bad;

    initial begin
        $readmemh("data/pre_in.mem", xin);
        $readmemh("data/pre_exp.mem", exp);

        oc  = 0;
        bad = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            x        = $signed(xin[i]);
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);          // 冲掉最后一拍

        if (oc != LEN) begin
            $display("TEST FAIL : out count=%0d want %0d", oc, LEN);
            bad = bad + 1;
        end
        if (bad == 0)
            $display("TEST PASS : pre_emph %0d samples bit-exact vs python", LEN);
        else
            $display("TEST FAIL : bad=%0d", bad);
        $finish;
    end

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < LEN && y !== exp[oc]) begin
                if (bad < 8)
                    $display("[ERR] sample %0d y=%06h exp=%06h", oc, y, exp[oc]);
                bad = bad + 1;
            end
            oc = oc + 1;
        end
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
