//------------------------------------------------------------------------------
// tb_cmd_matcher.v   每帧 13 维 MFCC → 最小距离模板 id，与 python 期望一致
//   ../../data/cmd_frames.mem(32帧×13) + cmd_ids_exp.mem(每帧期望 id)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_cmd_matcher;

    localparam NF = 32;         // 帧数
    localparam DIM = 13;
    localparam TL = NF * DIM;

    reg clk = 1'b0, rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg signed [15:0] in_v = 0;
    wire out_valid;
    wire [1:0] id;
    wire [31:0] dmin;

    cmd_matcher DUT (
        .clk(clk), .rst_n(rst_n),
        .mfcc_valid(in_valid), .mfcc_data(in_v),
        .cmd_valid(out_valid), .cmd_id(id), .cmd_dist_min(dmin)
    );

    always #10 clk = ~clk;

    reg [15:0] fr[0:TL-1];
    reg [1:0]  ex[0:NF-1];
    integer i, oc, err;

    always @(posedge clk) begin
        if (out_valid) begin
            if (oc < NF && id !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] frame%0d id=%0d want=%0d", oc, id, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("../../data/cmd_frames.mem", fr);
        $readmemh("../../data/cmd_ids_exp.mem", ex);
        oc = 0; err = 0;
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        for (i = 0; i < TL; i = i + 1) begin
            in_v     = $signed(fr[i]);
            in_valid = 1'b1;
            @(posedge clk);
        end
        in_valid = 1'b0;
        repeat(6) @(posedge clk);
        if (err == 0 && oc == NF)
            $display("TEST PASS : %0d frames cmd_id exact vs python", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #400000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
