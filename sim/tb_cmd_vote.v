//------------------------------------------------------------------------------
// tb_cmd_vote.v   滑动窗口命令众数与 python 期望一致(VOTE_N=8)
//   ../../data/cmd_ids_exp.mem(每帧 id) → ../../data/cmd_vote_exp.mem(从第 8 帧起决策 id)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_cmd_vote;

    localparam NF = 32;

    reg clk = 1'b0, rst_n = 1'b0;
    reg valid = 1'b0;
    reg [1:0] cid = 0;
    wire d_valid;
    wire [1:0] d_id;

    cmd_vote #(.VOTE_N(8), .NUM(4)) DUT (
        .clk(clk), .rst_n(rst_n), .cmd_valid(valid), .cmd_id(cid),
        .decision_valid(d_valid), .cmd_id_out(d_id), .frames_seen()
    );

    always #10 clk = ~clk;

    reg [1:0] ids[0:NF-1];
    reg [1:0] ex[0:NF-8-1];
    integer i, oc, err;

    always @(posedge clk) begin
        if (d_valid) begin
            if (oc < (NF-8) && d_id !== ex[oc]) begin
                if (err < 8)
                    $display("[ERR] dec%0d id=%0d want=%0d", oc, d_id, ex[oc]);
                err = err + 1;
            end
            oc = oc + 1;
        end
    end

    initial begin
        $readmemh("../../data/cmd_ids_exp.mem", ids);
        $readmemh("../../data/cmd_vote_exp.mem", ex);
        oc = 0; err = 0;
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        for (i = 0; i < NF; i = i + 1) begin
            cid   = ids[i];
            valid = 1'b1;
            @(posedge clk);
        end
        valid = 1'b0;
        repeat(4) @(posedge clk);
        if (err == 0 && oc == (NF-8))
            $display("TEST PASS : %0d command decisions exact", oc);
        else
            $display("TEST FAIL : oc=%0d err=%0d", oc, err);
        $finish;
    end

    initial #200000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
