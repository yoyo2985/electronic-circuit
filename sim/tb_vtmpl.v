//------------------------------------------------------------------------------
// tb_vtmpl.v   C2-lite 模板距离精确比对
//   data/vtmpl.mem + vvec.mem + vdist_exp.mem + vmatch_exp.mem (py/gen_vtempl_vec.py)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_vtmpl;

    localparam DIM = 4;
    localparam NVEC = 2;
    localparam LEN = DIM * NVEC;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [15:0] in_v = 0;
    wire out_valid;
    wire [31:0] out_dist;
    wire out_match;

    vtmpl #(.DIM(DIM), .TH(500)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_v(in_v),
        .out_valid(out_valid), .out_dist(out_dist), .out_match(out_match)
    );

    always #10 clk = ~clk;

    reg [15:0] vv[0:LEN-1];
    reg [31:0] ed[0:NVEC-1];
    reg [0:0]  em[0:NVEC-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < NVEC) begin
                if (out_dist !== ed[oc]) begin
                    if (err < 4)
                        $display("[ERR] vec%0d dist %0d want %0d", oc, out_dist, ed[oc]);
                    err = err + 1;
                end
                if (out_match !== em[oc]) begin
                    if (err < 4)
                        $display("[ERR] vec%0d match %b want %b", oc, out_match, em[oc]);
                    err = err + 1;
                end
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/vvec.mem", vv);
        $readmemh("data/vdist_exp.mem", ed);
        $readmemh("data/vmatch_exp.mem", em);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            in_v     = $signed(vv[i]);
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err == 0 && oc == NVEC)
            $display("TEST PASS : %0d vectors matched exact vs python", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
