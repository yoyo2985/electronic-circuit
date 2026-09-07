`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_virtual_motor.v   虚拟电机验证
//   1) cmd=+100度/秒：位置持续上升，在 180 顶住(at_max, pos_deg=180)，速度归零
//   2) cmd=-100度/秒：位置下降回到 0(at_min)
//------------------------------------------------------------------------------
module tb_virtual_motor;
    reg clk = 0;
    reg rst_n = 0;
    reg signed [19:0] cmd = 0;
    wire tick;
    wire at_max, at_min;
    wire [9:0] pos_deg;
    wire signed [19:0] vel;

    // 每 4 拍一个控制 tick
    reg [1:0] tc = 0;
    always @(posedge clk) begin
        if (!rst_n) tc <= 2'd0;
        else        tc <= tc + 2'd1;
    end
    assign tick = (tc == 2'd0);

    virtual_motor #(
        .MAX_POS_DEG(9'd180), .MAX_SPD_DEG_S(16'd100), .TAU_MS(16'd20)
    ) dut (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick), .cmd(cmd),
        .at_max(at_max), .at_min(at_min), .pos_deg(pos_deg), .vel(vel)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    initial begin
        err = 0;
        $display("=== tb_virtual_motor start ===");
        cmd = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // ---- 正转：冲到 180 ----
        cmd = 100 * 1024;
        cyc = 0;
        while (!at_max && cyc < 100000) begin @(posedge clk); cyc = cyc + 1; end
        if (at_max && pos_deg == 180)
            $display("PASS 正转顶住: pos=%0d (cyc=%0d)", pos_deg, cyc);
        else begin $display("FAIL 正转: at_max=%b pos=%0d", at_max, pos_deg); err = err + 1; end
        // 顶住后速度应归零
        repeat (20) @(posedge clk);
        if (vel == 0)
            $display("PASS 顶住后 vel=0");
        else begin $display("FAIL 顶住后 vel=%0d", vel); err = err + 1; end

        // ---- 反转：回到 0 ----
        cmd = -100 * 1024;
        cyc = 0;
        while (!at_min && cyc < 100000) begin @(posedge clk); cyc = cyc + 1; end
        if (at_min && pos_deg == 0)
            $display("PASS 反转回到0: pos=%0d (cyc=%0d)", pos_deg, cyc);
        else begin $display("FAIL 反转: at_min=%b pos=%0d", at_min, pos_deg); err = err + 1; end

        if (err == 0)
            $display("=== tb_virtual_motor PASS ===");
        else
            $display("=== tb_virtual_motor FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
