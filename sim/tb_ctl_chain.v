//------------------------------------------------------------------------------
// tb_ctl_chain.v   决策→轮速 链端到端比对
//   data/ct_vad.mem + ct_auth.mem + ct_dir.mem + ct_vl.mem + ct_vr.mem
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_ctl_chain;

    localparam LEN = 12;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_vad = 0, in_auth = 0;
    reg [1:0] in_dir = 0;
    wire out_valid;
    wire signed [7:0] vl, vr;

    ctl_chain DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_vad(in_vad), .in_auth(in_auth), .in_dir(in_dir),
        .out_valid(out_valid), .vl(vl), .vr(vr)
    );

    always #10 clk = ~clk;

    reg vm[0:LEN-1];
    reg am[0:LEN-1];
    reg [1:0] dm[0:LEN-1];
    reg [7:0] evl[0:LEN-1];
    reg [7:0] evr[0:LEN-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < LEN && (vl !== evl[oc] || vr !== evr[oc])) begin
                if (err < 8)
                    $display("[ERR] w%0d vl=%0d vr=%0d want %0d/%0d", oc, vl, vr,
                             $signed(evl[oc]), $signed(evr[oc]));
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/ct_vad.mem", vm);
        $readmemh("data/ct_auth.mem", am);
        $readmemh("data/ct_dir.mem", dm);
        $readmemh("data/ct_vl.mem", evl);
        $readmemh("data/ct_vr.mem", evr);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            in_vad   = vm[i];
            in_auth  = am[i];
            in_dir   = dm[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(4) @(posedge clk);

        if (err == 0 && oc == LEN)
            $display("TEST PASS : %0d chain decisions->wheels exact", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
