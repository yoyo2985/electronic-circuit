//------------------------------------------------------------------------------
// tb_log2_lut.v   B3-4b 定点 log2 精确比对
//   data/log2_lut.mem + log_in.mem + log_exp.mem 由 py/gen_log_vec.py 生成。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_log2_lut;

    localparam XW = 48;
    localparam LEN = 17;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [XW-1:0] in_x = 0;
    wire out_valid;
    wire [15:0] out_l;

    log2_lut #(.XW(XW), .FW(8), .BW(6)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_x(in_x),
        .out_valid(out_valid), .out_l(out_l)
    );

    always #10 clk = ~clk;

    reg [XW-1:0] xin[0:LEN-1];
    reg [15:0]   exp[0:LEN-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < LEN && out_l !== exp[oc]) begin
                if (err < 8)
                    $display("[ERR] i%0d got=%0d want=%0d", oc, out_l, exp[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/log_in.mem", xin);
        $readmemh("data/log_exp.mem", exp);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            in_x     = xin[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err == 0 && oc == LEN)
            $display("TEST PASS : log2_lut %0d values exact vs python", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #300000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
