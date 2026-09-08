//------------------------------------------------------------------------------
// tb_mfcc_quant.v   B5.2 定标精确比对（QS=0 与 QS=2 两条例化）
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_mfcc_quant;

    localparam LEN = 15;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [31:0] in_val = 0;

    wire ov0; wire signed [15:0] q0;
    wire ov2; wire signed [15:0] q2;
    mfcc_quant #(.QS(0)) u0 (.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_val(in_val),
                             .out_valid(ov0),.out_q(q0));
    mfcc_quant #(.QS(2)) u2 (.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_val(in_val),
                             .out_valid(ov2),.out_q(q2));

    always #10 clk = ~clk;

    reg [31:0] vin[0:LEN-1];
    reg [15:0] e0[0:LEN-1];
    reg [15:0] e2[0:LEN-1];

    integer i, oc0, oc2, err;

    always @(posedge clk) begin
        if (ov0) begin
            if (oc0 < LEN && q0 !== $signed(e0[oc0])) err = err + 1;
            oc0 = oc0 + 1;
        end
        if (ov2) begin
            if (oc2 < LEN && q2 !== $signed(e2[oc2])) err = err + 1;
            oc2 = oc2 + 1;
        end
    end

    initial begin
        $readmemh("data/mq_in.mem", vin);
        $readmemh("data/mq_exp0.mem", e0);
        $readmemh("data/mq_exp2.mem", e2);
        oc0=0; oc2=0; err=0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            in_val   = $signed(vin[i]);
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err==0 && oc0==LEN && oc2==LEN)
            $display("TEST PASS : mfcc_quant QS0/QS2 exact (incl sat extremes)");
        else
            $display("TEST FAIL : oc0=%0d oc2=%0d err=%0d", oc0, oc2, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
