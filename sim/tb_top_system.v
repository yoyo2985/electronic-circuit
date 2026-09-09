`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_system.v   top_system 集成验证
//   1) 按 9,0 → entry=90；按 ENTER(11) → 状态机 MOVE → 收敛 HOLD(pos≈90)
//   2) fault_sw=1 → FAULT；置0 + 按 CLR(10) → 回到非故障
//------------------------------------------------------------------------------
module tb_top_system;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    reg fault_sw = 0;
    wire tx;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;
    wire buzzer_out;

    top_system #(.MS_DIV(4), .VEL_DEG_S(250), .TELEM_MS(30)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .fault_sw(fault_sw), .tx(tx), .seg(seg), .dig_cs(dig_cs), .led(led),
        .buzzer_out(buzzer_out)
    );

    // 监测蜂鸣器是否被触发拉高过
    reg beep_seen = 0;
    always @(posedge clk) begin
        if (!rst_n)      beep_seen <= 1'b0;
        else if (buzzer_out) beep_seen <= 1'b1;
    end

    always #10 clk = ~clk;

    // 键盘模型
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

    integer i, err;
    task automatic press_label(input integer k);
        begin
            pr = k >> 2; pc = k & 2'd3;
            press = 1'b1;
            i = 0; while (!dut.key_event && i < 20000) begin @(posedge clk); i = i + 1; end
            press = 1'b0;
            i = 0; while (dut.key_event && i < 20000) begin @(posedge clk); i = i + 1; end
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        err = 0;
        $display("=== tb_top_system start ===");
        press = 0; pr = 0; pc = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // 输入 90
        press_label(9);
        press_label(0);
        if (dut.u_ti.entry == 9'd90)
            $display("PASS 输入 90");
        else begin $display("FAIL entry=%0d", dut.u_ti.entry); err = err + 1; end
        if (beep_seen)
            $display("PASS 数字键触发蜂鸣");
        else begin $display("FAIL 数字键未触发蜂鸣"); err = err + 1; end

        // ENTER 启动
        press_label(11);
        // 等状态机进入 MOVE
        i = 0;
        while (!(dut.u_fsm.state == 3'd2) && i < 10000) begin @(posedge clk); i = i + 1; end
        if (dut.u_fsm.state == 3'd2) $display("PASS 进入 MOVE");
        else begin $display("FAIL 未进 MOVE state=%0d", dut.u_fsm.state); err = err + 1; end

        // 等收敛 HOLD & pos≈90
        i = 0;
        while (!(dut.u_fsm.state == 3'd3) && i < 200000) begin @(posedge clk); i = i + 1; end
        if (dut.u_fsm.state == 3'd3 && dut.pos >= 88 && dut.pos <= 92)
            $display("PASS 收敛 HOLD pos=%0d", dut.pos);
        else begin
            $display("FAIL 未收敛: state=%0d pos=%0d", dut.u_fsm.state, dut.pos);
            err = err + 1;
        end

        // 强故障
        fault_sw = 1;
        repeat (3) @(posedge clk);
        if (dut.u_fsm.state == 3'd4)
            $display("PASS 强故障→FAULT");
        else begin $display("FAIL 未进 FAULT state=%0d", dut.u_fsm.state); err = err + 1; end

        // 撤故障 + CLR 确认
        fault_sw = 0;
        press_label(10);
        repeat (5) @(posedge clk);
        if (dut.u_fsm.state == 3'd0)
            $display("PASS CLR→IDLE");
        else begin $display("FAIL 未回 IDLE state=%0d", dut.u_fsm.state); err = err + 1; end

        if (err == 0) $display("=== tb_top_system PASS ===");
        else          $display("=== tb_top_system FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
