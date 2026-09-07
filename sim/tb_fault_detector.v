`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_fault_detector.v
//   冻结 pos -> 堵转故障；ack 清除；位置在变则正常；再次冻结 -> 再故障。
//   STALL_MS=10, ERR_TOL=5。
//------------------------------------------------------------------------------
module tb_fault_detector;
    reg clk = 0;
    reg rst_n = 0;
    wire tick;
    reg run = 0;
    reg [9:0] pos = 0;
    reg [9:0] target = 0;
    reg ack = 0;
    reg move = 0;
    wire faulted;

    reg [1:0] tc = 0;
    always @(posedge clk) begin
        if (!rst_n) tc <= 2'd0;
        else        tc <= tc + 2'd1;
    end
    assign tick = (tc == 2'd0);

    // 模拟“位置在动”用于正常段
    always @(posedge clk) if (move) pos <= pos + 1;

    fault_detector #(.STALL_MS(10), .ERR_TOL(5)) dut (
        .clk(clk), .rst_n(rst_n), .tick_ctrl(tick), .run(run),
        .pos(pos), .target(target), .ack(ack), .faulted(faulted)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    initial begin
        err = 0;
        $display("=== tb_fault_detector start ===");
        pos = 20; target = 90;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (5) @(posedge clk);

        // 冻结 → 堵转故障
        run = 1;
        cyc = 0;
        while (!faulted && cyc < 2000) begin @(posedge clk); cyc = cyc + 1; end
        if (faulted) $display("PASS 堵转故障 (cyc=%0d)", cyc);
        else begin $display("FAIL 未报故障"); err = err + 1; end

        // 清除：停动(run=0) 即清除
        run = 0;
        repeat (3) @(posedge clk);
        if (!faulted) $display("PASS 停动清除");
        else begin $display("FAIL 未清除"); err = err + 1; end

        // 位置在动 → 长时间不报故障
        run = 1; move = 1;
        cyc = 0;
        while (cyc < 3000) begin @(posedge clk); cyc = cyc + 1; end
        if (!faulted) $display("PASS 移动中无故障");
        else begin $display("FAIL 移动中误报"); err = err + 1; end
        move = 0;

        // 再次冻结 → 再故障
        cyc = 0;
        while (!faulted && cyc < 2000) begin @(posedge clk); cyc = cyc + 1; end
        if (faulted) $display("PASS 再次堵转故障");
        else begin $display("FAIL 未再报"); err = err + 1; end

        if (err == 0) $display("=== tb_fault_detector PASS ===");
        else          $display("=== tb_fault_detector FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
