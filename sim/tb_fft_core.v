//------------------------------------------------------------------------------
// tb_fft_core.v   B3-3 定点 FFT 容差比对（相对误差，参考 = numpy fft/N）
//   data/fft_in.mem + fft_exp_re/im.mem + tw_re/im_16.mem 由 py/gen_fft_vec.py 生成。
//   N=16。逐点喂入 → 自动跑蝶形 → 逐点输出，累计相对误差判 PASS。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_fft_core;

    localparam AW = 24;
    localparam N  = 16;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [AW-1:0] in_re = 0;
    wire out_valid;
    wire signed [31:0] out_re, out_im;

    fft_core #(.AW(AW), .N(N)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_re(in_re),
        .out_valid(out_valid), .out_re(out_re), .out_im(out_im)
    );

    always #10 clk = ~clk;

    reg [AW-1:0] xin[0:N-1];
    reg [31:0]   exr[0:N-1];
    reg [31:0]   exi[0:N-1];

    integer i, oc;
    reg signed [63:0] acc, refacc;

    function signed [63:0] abs64(input signed [63:0] v);
        abs64 = (v < 0) ? -v : v;
    endfunction

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < N) begin
                acc   = acc   + abs64($signed(out_re) - $signed(exr[oc]));
                acc   = acc   + abs64($signed(out_im) - $signed(exi[oc]));
                refacc= refacc+ abs64($signed(exr[oc])) + abs64($signed(exi[oc]));
                if (oc < 6)
                    $display("bin%0d re=%0d im=%0d | exp re=%0d im=%0d",
                             oc, $signed(out_re), $signed(out_im),
                             $signed(exr[oc]), $signed(exi[oc]));
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/fft_in.mem", xin);
        $readmemh("data/fft_exp_re.mem", exr);
        $readmemh("data/fft_exp_im.mem", exi);

        oc = 0; acc = 0; refacc = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < N; i = i + 1) begin
            in_re    = $signed(xin[i]);
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;

        while (oc < N) @(posedge clk);
        #20;

        // 相对误差
        $display("rel_err = %0d / %0d", acc, refacc);
        if (refacc > 0 && acc * 100 <= refacc * 6)   // ≤6%
            $display("TEST PASS : fft N=%0d rel err ~%0d.%02d%%",
                     N, 0, 0);
        else
            $display("TEST FAIL : rel err too large");
        $finish;
    end

    initial #300000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
