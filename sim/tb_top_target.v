`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_target.v   top_target 胶水验证
//   模拟按 KEY4、KEY5 -> entry=45；KEY11(ENTER)-> target=45 valid=1；
//   KEY10(CLR) -> 清空。
//------------------------------------------------------------------------------
module tb_top_target;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;

    top_target #(.MS_DIV(8), .DEBOUNCE_N(2)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .seg(seg), .dig_cs(dig_cs), .led(led)
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

    integer i, err;
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

    initial begin
        err = 0;
        $display("=== tb_top_target start ===");
        press = 0; pr = 0; pc = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        press_label(4);
        if (dut.entry == 9'd4) $display("PASS 按4: entry=%0d", dut.entry);
        else begin $display("FAIL 按4: entry=%0d", dut.entry); err = err + 1; end

        press_label(5);
        if (dut.entry == 9'd45) $display("PASS 按5: entry=%0d", dut.entry);
        else begin $display("FAIL 按5: entry=%0d", dut.entry); err = err + 1; end

        press_label(11);       // ENTER
        if (dut.target == 9'd45 && dut.target_valid)
            $display("PASS ENTER: target=%0d valid=%b", dut.target, dut.target_valid);
        else begin $display("FAIL ENTER: target=%0d valid=%b", dut.target, dut.target_valid); err = err + 1; end

        press_label(10);       // CLR
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
