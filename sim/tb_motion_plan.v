//------------------------------------------------------------------------------
// tb_motion_plan.v   动作→轮速精确比对
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_motion_plan;

    localparam LEN = 8;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [2:0] action = 0;
    wire out_valid;
    wire signed [7:0] vl, vr;

    motion_plan #(.VF(80), .VT(50)) DUT (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .action(action),
        .out_valid(out_valid), .vl(vl), .vr(vr)
    );

    always #10 clk = ~clk;

    reg [2:0] a[0:LEN-1];
    reg [7:0] el[0:LEN-1];
    reg [7:0] er[0:LEN-1];

    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < LEN && (vl !== el[oc] || vr !== er[oc])) begin
                if (err < 8)
                    $display("[ERR] %0d vl=%0d vr=%0d want %0d/%0d", oc, vl, vr,
                             $signed(el[oc]), $signed(er[oc]));
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("data/ml_act.mem", a);
        $readmemh("data/ml_vl.mem", el);
        $readmemh("data/ml_vr.mem", er);
        oc = 0; err = 0;

        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < LEN; i = i + 1) begin
            action   = a[i];
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(3) @(posedge clk);

        if (err == 0 && oc == LEN)
            $display("TEST PASS : %0d actions -> wheels exact", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
