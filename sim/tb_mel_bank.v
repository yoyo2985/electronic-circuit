//------------------------------------------------------------------------------
// tb_mel_bank.v   B3-4a Mel 能量累加精确比对
//   data/mel_pow.mem + mel_coef.mem + mel_exp.mem 由 py/gen_mel_vec.py 生成。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_mel_bank;

    localparam NB = 33, M = 20;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [31:0] in_pow = 0;
    wire out_valid;
    wire [63:0] out_mel;

    mel_bank #(.NB(NB), .M(M), .CFQ(12)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_pow(in_pow),
        .out_valid(out_valid), .out_mel(out_mel)
    );

    always #10 clk = ~clk;

    reg [31:0] pw[0:NB-1];
    reg [63:0] ex[0:M-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < M && out_mel !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] mel%0d got %0d want %0d", oc, out_mel, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/mel_pow.mem", pw);
        $readmemh("data/mel_exp.mem", ex);
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

        if (err == 0)
            $display("TEST PASS : %0d mel bins exact vs python", oc);
        else
            $display("TEST FAIL : err=%0d", err);
        $finish;
    end

    initial #300000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
