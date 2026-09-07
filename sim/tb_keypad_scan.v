`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_keypad_scan.v   键盘扫描验证
//   行为模型：按住(pr,pc)时，仅当 dut 扫到第 pr 行(row_out 对应位为低)，
//             才把第 pc 列拉低(其他列/时刻全 1)。列上有“上拉”模拟。
//   验证点：按下一个键只产生 1 次 key_event、key_idx=row*4+col；
//           松开后不再有事件；再按另一键正确更新。
//------------------------------------------------------------------------------
module tb_keypad_scan;
    reg clk = 0;
    reg rst_n = 0;
    wire tick_1ms;
    wire [3:0] col_in;
    wire [3:0] row_out;
    wire key_event;
    wire [3:0] key_idx;

    // 被测：DEBOUNCE_N=2（快照连续 2 次一致即稳定）
    keypad_scan #(.DEBOUNCE_N(2)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .col_in(col_in), .row_out(row_out),
        .key_event(key_event), .key_idx(key_idx)
    );

    // 1ms 节拍（等价 clock_enable #(8)：每 8 拍一个脉冲，留足同步器 2 拍余量）
    reg [2:0] tcnt = 3'd0;
    always @(posedge clk) begin
        if (!rst_n) tcnt <= 3'd0;
        else        tcnt <= tcnt + 3'd1;
    end
    assign tick_1ms = (tcnt == 3'd0);

    always #10 clk = ~clk;   // 50 MHz

    // ---- 键盘行为模型 ----
    reg press;
    reg [1:0] pr, pc;
    reg [1:0] row_sel;
    always @(*) begin
        case (row_out)
            4'b1110: row_sel = 2'd0;
            4'b1101: row_sel = 2'd1;
            4'b1011: row_sel = 2'd2;
            4'b0111: row_sel = 2'd3;
            default: row_sel = 2'd0;
        endcase
    end
    assign col_in = (press && row_sel == pr) ? (4'hF ^ (4'b0001 << pc)) : 4'hF;

    // ---- 事件计数（采样每个时钟沿）----
    integer evcount;
    always @(posedge clk) begin
        if (!rst_n) evcount <= 0;
        else if (key_event) evcount <= evcount + 1;
    end

    integer i, err;
    initial begin
        err = 0;
        $display("=== tb_keypad_scan start ===");
        press = 0; pr = 0; pc = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (30) @(posedge clk);

        // ---- 空载：无事件，key_idx=0 ----
        if (evcount == 0)
            $display("PASS 空载: 无事件");
        else begin $display("FAIL 空载: evcount=%0d", evcount); err = err + 1; end

        // ---- 按下 (row=1,col=3) => 键号 7 ----
        pr = 2'd1; pc = 2'd3; press = 1'b1;
        // 等第一个事件
        i = 0;
        while (!key_event && i < 800) begin @(posedge clk); i = i + 1; end
        if (key_event && key_idx == 4'd7)
            $display("PASS 按下键7: 收到事件 key_idx=7 (cyc=%0d)", i);
        else begin
            $display("FAIL 按下键7: key_event=%b key_idx=%0d", key_event, key_idx);
            err = err + 1;
        end
        // 继续按住 60 拍，确认只产生一次事件
        repeat (60) @(posedge clk);
        if (evcount == 1)
            $display("PASS 按住期间事件仅1次 (evcount=%0d)", evcount);
        else begin $display("FAIL 按住期间 evcount=%0d(期望1)", evcount); err = err + 1; end

        // ---- 松开：无新事件，key_idx 保留 ----
        press = 1'b0;
        repeat (40) @(posedge clk);
        if (evcount == 1 && key_idx == 4'd7)
            $display("PASS 松开: 无新事件, key_idx 保持 7");
        else begin $display("FAIL 松开: evcount=%0d key_idx=%0d", evcount, key_idx); err = err + 1; end

        // ---- 再按 (row=0,col=2) => 键号 2 ----
        pr = 2'd0; pc = 2'd2; press = 1'b1;
        i = 0;
        while (!key_event && i < 800) begin @(posedge clk); i = i + 1; end
        if (key_event && key_idx == 4'd2)
            $display("PASS 再按键2: key_idx=2");
        else begin
            $display("FAIL 再按键2: key_event=%b key_idx=%0d", key_event, key_idx);
            err = err + 1;
        end
        press = 1'b0;
        repeat (20) @(posedge clk);

        if (err == 0)
            $display("=== tb_keypad_scan PASS ===");
        else
            $display("=== tb_keypad_scan FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
