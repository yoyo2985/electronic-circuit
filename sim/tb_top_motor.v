`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_motor.v   top_motor 胶水验证
//   自动往复：先从 0 到 180(at_max)、再回到 0(at_min)；检查位置/方向。
//   仿真参数：MS_DIV=8、SPD_DEG_S=40。
//------------------------------------------------------------------------------
module tb_top_motor;
    reg clk = 0;
    reg rst_n = 0;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;

    top_motor #(.MS_DIV(8), .SPD_DEG_S(40)) dut (
        .clk(clk), .rst_n(rst_n), .seg(seg), .dig_cs(dig_cs), .led(led)
    );

    always #10 clk = ~clk;

    integer cyc, err;
    initial begin
        err = 0;
        $display("=== tb_top_motor start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // 先确认位置确实在增长
        cyc = 0;
        while (dut.pos_deg < 9'd30 && cyc < 50000) begin @(posedge clk); cyc = cyc + 1; end
        if (dut.pos_deg >= 9'd30)
            $display("PASS 位置增长: pos=%0d", dut.pos_deg);
        else begin $display("FAIL 位置未增长: pos=%0d", dut.pos_deg); err = err + 1; end

        // 到 180 顶住
        cyc = 0;
        while (!dut.at_max && cyc < 300000) begin @(posedge clk); cyc = cyc + 1; end
        if (dut.at_max && dut.pos_deg == 180)
            $display("PASS 顶到180: pos=%0d", dut.pos_deg);
        else begin $display("FAIL 到180: at_max=%b pos=%0d", dut.at_max, dut.pos_deg); err = err + 1; end

        // 回到 0
        cyc = 0;
        while (!dut.at_min && cyc < 300000) begin @(posedge clk); cyc = cyc + 1; end
        if (dut.at_min && dut.pos_deg == 0)
            $display("PASS 回到0: pos=%0d", dut.pos_deg);
        else begin $display("FAIL 回0: at_min=%b pos=%0d", dut.at_min, dut.pos_deg); err = err + 1; end

        if (err == 0)
            $display("=== tb_top_motor PASS ===");
        else
            $display("=== tb_top_motor FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
