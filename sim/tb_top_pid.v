`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_pid.v   top_pid 胶水验证
//   SW1=0 → target 40：应收敛到位；SW1=1 → target 120：应收敛到位。
//   检查 at_target 点亮、位置正确。
//------------------------------------------------------------------------------
module tb_top_pid;
    reg clk = 0;
    reg rst_n = 0;
    reg sw1 = 0;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;

    top_pid #(.MS_DIV(4)) dut (
        .clk(clk), .rst_n(rst_n), .sw1(sw1),
        .seg(seg), .dig_cs(dig_cs), .led(led)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    initial begin
        err = 0;
        $display("=== tb_top_pid start ===");
        sw1 = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // target=40 收敛
        cyc = 0;
        while (!dut.at_target && cyc < 60000) begin @(posedge clk); cyc = cyc + 1; end
        if (dut.at_target && dut.pos >= 38 && dut.pos <= 42)
            $display("PASS SW1=0 → pos=%0d 到位", dut.pos);
        else begin $display("FAIL target40: pos=%0d at=%b", dut.pos, dut.at_target); err = err + 1; end

        // 切换 SW1 → target 120 收敛
        sw1 = 1;
        @(posedge clk);                 // 等一拍让组合 target 更新、对齐采样
        cyc = 0;
        while (!dut.at_target && cyc < 120000) begin @(posedge clk); cyc = cyc + 1; end
        if (dut.at_target && dut.pos >= 118 && dut.pos <= 122)
            $display("PASS SW1=1 → pos=%0d 到位", dut.pos);
        else begin
            $display("FAIL target120: pos=%0d target=%0d at=%b", dut.pos, dut.target, dut.at_target);
            err = err + 1;
        end

        if (err == 0)
            $display("=== tb_top_pid PASS ===");
        else
            $display("=== tb_top_pid FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
