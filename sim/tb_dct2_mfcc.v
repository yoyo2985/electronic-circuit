//------------------------------------------------------------------------------
// tb_dct2_mfcc.v   B3-5 DCT-II 精确比对
//   data/dct_basis.mem + dct_in.mem + dct_exp.mem 由 py/gen_dct_vec.py 生成。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_dct2_mfcc;

    localparam M = 20, K = 13;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [15:0] in_x = 0;
    wire out_valid;
    wire [31:0] out_c;

    dct2_mfcc #(.M(M), .K(K), .DQ(12)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_x(in_x),
        .out_valid(out_valid), .out_c(out_c)
    );

    always #10 clk = ~clk;

    reg [15:0] xin[0:M-1];
    reg [31:0] ex[0:K-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < K && out_c !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] c%0d got=%0d want=%0d", oc, $signed(out_c), $signed(ex[oc]));
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/dct_in.mem", xin);
        $readmemh("data/dct_exp.mem", ex);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < M; i = i + 1) begin
            in_x     = xin[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;

        while (oc < K) @(posedge clk);
        #20;

        if (err == 0 && oc == K)
            $display("TEST PASS : %0d DCT coeffs exact vs python", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #300000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
