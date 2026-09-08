//------------------------------------------------------------------------------
// tb_logmel_chain.v   定点 log-mel 链精确比对
//   data/mel_pow.mem(输入) + mel_coef.mem + logmel_exp.mem(期望 log)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_logmel_chain;

    localparam NB = 9, M = 6;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [31:0] in_pow = 0;
    wire out_valid;
    wire [15:0] out_logmel;

    logmel_chain #(.NB(NB), .M(M)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_pow(in_pow),
        .out_valid(out_valid), .out_logmel(out_logmel)
    );

    always #10 clk = ~clk;

    reg [31:0] pw[0:NB-1];
    reg [15:0] ex[0:M-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < M && out_logmel !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] logmel%0d got=%0d want=%0d", oc, out_logmel, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/mel_pow.mem", pw);
        $readmemh("data/logmel_exp.mem", ex);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < NB; i = i + 1) begin
            in_pow   = pw[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;

        while (oc < M) @(posedge clk);
        #20;

        if (err == 0 && oc == M)
            $display("TEST PASS : %0d logmel bins exact vs python", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #300000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
