// tb_beep_gen : 无源蜂鸣器方波脉冲音仿真
//
// 仿真加速策略：真实板上 tick_1ms 每 50_000 clk 一拍、蜂鸣 2kHz；
// 仿真里把 tick 加速为每 5 clk 一拍，并把 FREQ_HZ 提高到 500kHz，
// 使 HALF=50 clk，方波在几十个 tick 内即可观察到多次翻转。
//
// 检查项：
//   1. 触发后 buzzer 立即拉高；
//   2. 蜂鸣期间方波多次翻转（edges >= 3）；
//   3. DUR_MS 个 tick 后蜂鸣自动停止，buzzer 回到 0。
`timescale 1ns/1ps

module tb_beep_gen;

    // ---- 仿真参数 ----
    localparam CLK_FREQ_HZ  = 50_000_000; // 仿真时钟 50MHz（仅用于计算 HALF）
    localparam TICKS_PER_MS = 5;          // 每 5 个 clk 产生 1 个 tick_1ms
    localparam FREQ_HZ      = 500_000;    // HALF = 50 clk → 每 50 clk 翻转一次
    localparam DUR_MS       = 40;         // 蜂鸣持续 40 个 tick

    reg  clk = 0;
    reg  rst_n = 0;
    wire tick_1ms;
    reg  trigger = 0;
    wire buzzer;

    always #10 clk = ~clk;   // 20ns → 50MHz

    // tick_1ms：每 TICKS_PER_MS 个 clk 拉高 1 拍（tc==0 时）
    reg [3:0] tc = 0;
    always @(posedge clk) begin
        if (tc == TICKS_PER_MS - 1) tc <= 4'd0;
        else                         tc <= tc + 4'd1;
    end
    assign tick_1ms = (tc == 4'd0);

    beep_gen #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .FREQ_HZ(FREQ_HZ), .DUR_MS(DUR_MS))
        u_dut (.clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
               .trigger(trigger), .buzzer(buzzer));

    integer edges;
    reg    last_buzzer;
    integer i;

    initial begin
        edges = 0; last_buzzer = 0;

        repeat (10) @(posedge clk);   // 复位低电平保持
        rst_n = 1;

        // 等几个 tick 稳定后再触发
        repeat (TICKS_PER_MS * 3) @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // 观察 (DUR_MS+10) 个 tick，统计 buzzer 翻转次数
        repeat ((DUR_MS + 10) * TICKS_PER_MS) begin
            @(posedge clk);
            if (buzzer !== last_buzzer) begin
                edges = edges + 1;
                last_buzzer = buzzer;
            end
        end

        // ---- 判定 ----
        if (buzzer == 1'b0 && edges >= 3) begin
            $display("PASS: 蜂鸣结束 buzzer=0, 翻转 edges=%0d", edges);
        end else begin
            $display("FAIL: buzzer=%b edges=%0d (期望 0 且 >=3)", buzzer, edges);
        end
        $finish;
    end

endmodule
