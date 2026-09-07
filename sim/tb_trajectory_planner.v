`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_trajectory_planner.v
//   en=1 且 goal=120：ref_pos 单调升到 120 且不超调；再切 goal=40 降到 40。
//   VEL 用 250 加速仿真（STEP≈64/256≈0.25度/tick）。
//------------------------------------------------------------------------------
module tb_trajectory_planner;
    reg clk = 0;
    reg rst_n = 0;
    wire tick;
    reg en = 0;
    reg [9:0] goal = 0;
    reg [9:0] pos0 = 0;
    wire [9:0] ref_pos;

    reg [1:0] tc = 0;
    always @(posedge clk) begin
        if (!rst_n) tc <= 2'd0;
        else        tc <= tc + 2'd1;
    end
    assign tick = (tc == 2'd0);

    trajectory_planner #(.VEL_DEG_S(250)) dut (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick), .en(en),
        .goal(goal), .pos0(pos0), .ref_pos(ref_pos)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    reg [9:0] prev;
    initial begin
        err = 0; prev = 0;
        $display("=== tb_trajectory_planner start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (5) @(posedge clk);

        // 上升到 120
        goal = 120; en = 1;
        @(posedge clk);
        cyc = 0; prev = 0;
        while (!(ref_pos == 120) && cyc < 30000) begin
            @(posedge clk); cyc = cyc + 1;
            if (ref_pos > 120) begin $display("FAIL 超调: ref=%0d", ref_pos); err = err + 1; cyc = 99999; end
            if (ref_pos < prev) begin $display("FAIL 回退: %0d→%0d", prev, ref_pos); err = err + 1; cyc = 99999; end
            prev = ref_pos;
        end
        if (ref_pos == 120)
            $display("PASS 升到120: ref=%0d (cyc=%0d)", ref_pos, cyc);
        else begin $display("FAIL 未到120: ref=%0d", ref_pos); err = err + 1; end
        repeat (200) @(posedge clk);
        if (ref_pos == 120) $display("PASS 到120后保持");
        else begin $display("FAIL 120未保持 ref=%0d", ref_pos); err = err + 1; end

        // 下降到 40
        goal = 40;
        cyc = 0; prev = 120;
        while (!(ref_pos == 40) && cyc < 30000) begin
            @(posedge clk); cyc = cyc + 1;
            if (ref_pos < 40) begin $display("FAIL 下超: ref=%0d", ref_pos); err = err + 1; cyc = 99999; end
            if (ref_pos > prev) begin $display("FAIL 上升: %0d→%0d", prev, ref_pos); err = err + 1; cyc = 99999; end
            prev = ref_pos;
        end
        if (ref_pos == 40) $display("PASS 降到40: ref=%0d", ref_pos);
        else begin $display("FAIL 未到40: ref=%0d", ref_pos); err = err + 1; end

        if (err == 0) $display("=== tb_trajectory_planner PASS ===");
        else          $display("=== tb_trajectory_planner FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
