`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_clock_enable.v
// 验证：每 MS_DIV 个时钟产生一个 1 拍宽的 tick_1ms；复位期间无脉冲。
// 仿真把 MS_DIV 设小到 50，加速。
//------------------------------------------------------------------------------
module tb_clock_enable;
    localparam SIM_DIV = 50;
    reg clk = 0;
    reg rst_n = 0;
    wire tick;

    clock_enable #(.MS_DIV(SIM_DIV)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick)
    );

    always #10 clk = ~clk;   // 20 ns ⇒ 50 MHz

    integer cyc = 0, pulses = 0;
    initial begin
        $display("=== tb_clock_enable start (MS_DIV=%0d) ===", SIM_DIV);
        rst_n = 0;
        repeat (3) @(posedge clk);   // 复位几个时钟
        rst_n = 1;
        while (pulses < 5 && cyc < 400) begin
            @(posedge clk);
            cyc = cyc + 1;
            if (tick) begin
                pulses = pulses + 1;
                $display("tick #%0d  at cycle %0d", pulses, cyc);
            end
        end
        if (pulses == 5)
            $display("PASS: 收到 5 个 tick，周期约 %0d 个时钟/脉冲", SIM_DIV);
        else
            $display("CHECK: pulses=%0d cyc=%0d（看波形找原因）", pulses, cyc);
        $display("=== tb_clock_enable done ===");
        $finish;
    end
endmodule
