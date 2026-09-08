//------------------------------------------------------------------------------
// tb_direction3.v   D1 三态方向精确比对
//   data/dir_el.mem + dir_er.mem + dir_exp.mem (py/gen_direction3.py)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_direction3;

    localparam EW = 24;
    localparam LEN = 12;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [EW-1:0] el = 0, er = 0;
    wire out_valid;
    wire [1:0] dir;

    direction3 #(.EW(EW), .TH_ON(200), .TH_OFF(60)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .e_l(el), .e_r(er),
        .out_valid(out_valid), .dir(dir)
    );

    always #10 clk = ~clk;

    reg [EW-1:0] elm[0:LEN-1];
    reg [EW-1:0] erm[0:LEN-1];
    reg [1:0]    ex[0:LEN-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < LEN && dir !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] w%0d dir=%0d want=%0d", oc, dir, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/dir_el.mem", elm);
        $readmemh("data/dir_er.mem", erm);
        $readmemh("data/dir_exp.mem", ex);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            el       = elm[i];
            er       = erm[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err == 0 && oc == LEN)
            $display("TEST PASS : %0d windows direction exact", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
