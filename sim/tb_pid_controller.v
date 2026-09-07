`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_pid_controller.v   位置环 PID 闭环验证（PID + virtual_motor）
//   阶跃 target=90：应收敛到 |pos-90|<=2 且基本无超调；再阶跃 30 收敛。
//   cmd 受输出限幅(±61440=±60度/秒)。
//------------------------------------------------------------------------------
module tb_pid_controller;
    reg clk = 0;
    reg rst_n = 0;
    wire tick;
    reg [9:0] target = 0;
    wire signed [19:0] cmd;
    wire [9:0] pos;
    wire at_max, at_min;

    // 每 4 拍一个控制 tick
    reg [1:0] tc = 0;
    always @(posedge clk) begin
        if (!rst_n) tc <= 2'd0;
        else        tc <= tc + 2'd1;
    end
    assign tick = (tc == 2'd0);

    virtual_motor #(
        .MAX_POS_DEG(9'd180), .MAX_SPD_DEG_S(16'd60), .TAU_MS(16'd50)
    ) u_mot (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick), .cmd(cmd),
        .at_max(at_max), .at_min(at_min), .pos_deg(pos), .vel()
    );

    pid_controller u_pid (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick), .target(target), .pos(pos),
        .cmd(cmd)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    integer peak;
    initial begin
        err = 0; peak = 0;
        $display("=== tb_pid_controller start ===");
        target = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // ---- 阶跃到 90 ----
        target = 90;
        cyc = 0;
        while (!(pos > 88 && pos < 92) && cyc < 20000) begin
            @(posedge clk); cyc = cyc + 1;
            if (pos > peak) peak = pos;
        end
        // 稳定一段时间确认不再漂移
        cyc = 0;
        while (cyc < 4000) begin @(posedge clk); cyc = cyc + 1; end
        if (pos > 88 && pos < 92)
            $display("PASS 收敛到90: pos=%0d (峰值%0d)", pos, peak);
        else begin $display("FAIL 收敛到90: pos=%0d", pos); err = err + 1; end
        if (peak <= 96)
            $display("PASS 超调受限: 峰值=%0d", peak);
        else begin $display("FAIL 超调过大: 峰值=%0d", peak); err = err + 1; end

        // ---- 阶跃到 30 ----
        peak = 0; target = 30;
        cyc = 0;
        while (!(pos < 32 && pos > 28) && cyc < 20000) begin
            @(posedge clk); cyc = cyc + 1;
            if (pos < 30 && (30 - pos) > peak) peak = 30 - pos;   // 记录下冲
        end
        cyc = 0;
        while (cyc < 4000) begin @(posedge clk); cyc = cyc + 1; end
        if (pos > 28 && pos < 32)
            $display("PASS 收敛到30: pos=%0d", pos);
        else begin $display("FAIL 收敛到30: pos=%0d", pos); err = err + 1; end
        if (peak <= 4)
            $display("PASS 下冲受限: %0d", peak);
        else begin $display("FAIL 下冲过大: %0d", peak); err = err + 1; end

        if (err == 0)
            $display("=== tb_pid_controller PASS ===");
        else
            $display("=== tb_pid_controller FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
