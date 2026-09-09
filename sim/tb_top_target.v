`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_target.v   top_target(含蜂鸣器)胶水验证
//   模拟按 KEY4、KEY5 -> entry=45；KEY11(ENTER)-> target=45 valid=1；
//   KEY10(CLR) -> 清空。并验证三种按键各自触发音效、响完自动停止：
//     数字键(16 tick)/ENTER(24 tick)/CLR(20 tick)，时长互不相同且方波有翻转。
//   仿真加速：tick 每 MS_DIV 拍一拍；音效频率抬高使 HALF 变小、短时长内可见翻转。
//------------------------------------------------------------------------------
module tb_top_target;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;
    wire buzzer_out;

    localparam MS_DIV = 8;
    top_target #(
        .MS_DIV(MS_DIV), .DEBOUNCE_N(2),
        .BEEP_DIG_FREQ(500_000), .BEEP_DIG_DUR(16),   // HALF=50 拍
        .BEEP_CLR_FREQ(400_000), .BEEP_CLR_DUR(20),   // HALF=62 拍
        .BEEP_ENT_FREQ(1_000_000), .BEEP_ENT_DUR(24)  // HALF=25 拍
    ) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .seg(seg), .dig_cs(dig_cs), .led(led), .buzzer_out(buzzer_out)
    );

    always #10 clk = ~clk;

    // 键盘模型：按 key_idx=k 的键（row=k/4, col=k%4）
    reg press = 0;
    reg [1:0] pr, pc;
    reg [1:0] row_sel;
    always @(*) begin
        case (row)
            4'b1110: row_sel = 2'd0;
            4'b1101: row_sel = 2'd1;
            4'b1011: row_sel = 2'd2;
            4'b0111: row_sel = 2'd3;
            default: row_sel = 2'd0;
        endcase
    end
    assign col = (press && row_sel == pr) ? (4'hF ^ (4'b0001 << pc)) : 4'hF;

    integer i, err, edges, beep_len;
    reg last_bz;

    task automatic press_label(input integer k);
        begin
            pr = k >> 2; pc = k & 2'd3;
            press = 1'b1;
            i = 0; while (!dut.key_event && i < 3000) begin @(posedge clk); i = i + 1; end
            press = 1'b0;
            i = 0; while (dut.key_event && i < 3000) begin @(posedge clk); i = i + 1; end
            repeat (5) @(posedge clk);
        end
    endtask

    // 按键 + 验证音效：等待拉高、统计发声拍数/翻转次数（覆盖整个蜂鸣窗口）
    task automatic press_and_beep(input integer k, input integer dur_tick);
        integer c;
        begin
            press_label(k);
            i = 0; while (dut.buzzer_out !== 1'b1 && i < 2000) begin @(posedge clk); i = i + 1; end
            if (i >= 2000) begin
                $display("FAIL 按%0d: 无蜂鸣", k); err = err + 1;
            end else begin
                edges = 0; beep_len = 0; last_bz = 1'b0;
                // 固定窗口 (dur_tick+4) 个 tick，覆盖整个蜂鸣期（注意：不能用"静音N拍"判断
                // 结束，因为方波低半周期就有 HALF 拍）
                for (c = 0; c < (dur_tick + 4) * MS_DIV; c = c + 1) begin
                    @(posedge clk);
                    if (dut.buzzer_out !== 1'b0) beep_len = beep_len + 1;
                    if (dut.buzzer_out !== last_bz) begin
                        edges = edges + 1;
                        last_bz = dut.buzzer_out;
                    end
                end
                // 时长 ≈ dur_tick 个 tick（发声半周期≈总时长一半），方波翻转 >= 3 次，蜂鸣已结束回 0
                if (dut.buzzer_out == 1'b0 && edges >= 3 &&
                    beep_len >= (dur_tick - 4) * MS_DIV / 2 &&
                    beep_len <= (dur_tick + 4) * MS_DIV / 2) begin
                    $display("PASS 按%0d: 音效 len=%0d拍 edges=%0d", k, beep_len, edges);
                end else begin
                    $display("FAIL 按%0d: len=%0d拍 edges=%0d (期望~%0d拍, >=3翻转)",
                             k, beep_len, edges, dur_tick * MS_DIV);
                    err = err + 1;
                end
                repeat (4) @(posedge clk);
            end
        end
    endtask

    initial begin
        err = 0;
        $display("=== tb_top_target start ===");
        press = 0; pr = 0; pc = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        press_and_beep(4, 16);
        if (dut.entry == 9'd4) $display("PASS 按4: entry=%0d", dut.entry);
        else begin $display("FAIL 按4: entry=%0d", dut.entry); err = err + 1; end

        press_and_beep(5, 16);
        if (dut.entry == 9'd45) $display("PASS 按5: entry=%0d", dut.entry);
        else begin $display("FAIL 按5: entry=%0d", dut.entry); err = err + 1; end

        press_and_beep(11, 24);    // ENTER
        if (dut.target == 9'd45 && dut.target_valid)
            $display("PASS ENTER: target=%0d valid=%b", dut.target, dut.target_valid);
        else begin $display("FAIL ENTER: target=%0d valid=%b", dut.target, dut.target_valid); err = err + 1; end

        press_and_beep(10, 20);    // CLR
        if (!dut.target_valid && dut.entry == 9'd0)
            $display("PASS CLR: valid=%b entry=%0d", dut.target_valid, dut.entry);
        else begin $display("FAIL CLR: valid=%b entry=%0d", dut.target_valid, dut.entry); err = err + 1; end

        if (err == 0)
            $display("=== tb_top_target PASS ===");
        else
            $display("=== tb_top_target FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
