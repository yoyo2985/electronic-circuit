`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_target_input.v   目标输入验证
//   4,5 -> 45；再 5 -> 455>180 拒收(over_range)；CLR 清；
//   1,8,0 -> 180(最大值可入)；再 0 -> 拒收；ENTER -> target=180 valid；
//   CLR -> 取消 valid。
//------------------------------------------------------------------------------
module tb_target_input;
    reg clk = 0;
    reg rst_n = 0;
    reg key_event = 0;
    reg [3:0] key = 0;
    wire [8:0] entry, target;
    wire over_range, target_valid;

    target_input dut (
        .clk(clk), .rst_n(rst_n), .key_event(key_event), .key(key),
        .entry(entry), .target(target),
        .over_range(over_range), .target_valid(target_valid)
    );

    always #10 clk = ~clk;

    task automatic press(input [3:0] k);
        begin
            @(posedge clk); key_event = 1'b1; key = k;
            @(posedge clk); key_event = 1'b0;
            @(posedge clk);
        end
    endtask

    integer err;
    initial begin
        err = 0;
        $display("=== tb_target_input start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (3) @(posedge clk);

        press(4'd4);
        if (entry == 9'd4) $display("PASS 输入4: entry=%0d", entry);
        else begin $display("FAIL 输入4: entry=%0d", entry); err = err + 1; end

        press(4'd5);
        if (entry == 9'd45) $display("PASS 输入45: entry=%0d", entry);
        else begin $display("FAIL 输入45: entry=%0d", entry); err = err + 1; end

        press(4'd5);                      // 455 > 180 -> 拒收
        if (entry == 9'd45 && over_range)
            $display("PASS 输入455超限拒收: entry=%0d over=%b", entry, over_range);
        else begin $display("FAIL 超限: entry=%0d over=%b", entry, over_range); err = err + 1; end

        press(4'd10);                     // CLR
        if (entry == 9'd0) $display("PASS CLR: entry=%0d", entry);
        else begin $display("FAIL CLR: entry=%0d", entry); err = err + 1; end

        press(4'd1); press(4'd8); press(4'd0);     // 180
        if (entry == 9'd180) $display("PASS 输入180: entry=%0d", entry);
        else begin $display("FAIL 输入180: entry=%0d", entry); err = err + 1; end

        press(4'd0);                      // 1800 > 180 -> 拒收
        if (entry == 9'd180 && over_range)
            $display("PASS 180后再按0拒收: entry=%0d over=%b", entry, over_range);
        else begin $display("FAIL: entry=%0d over=%b", entry, over_range); err = err + 1; end

        press(4'd11);                     // ENTER
        if (target == 9'd180 && target_valid)
            $display("PASS ENTER: target=%0d valid=%b", target, target_valid);
        else begin $display("FAIL ENTER: target=%0d valid=%b", target, target_valid); err = err + 1; end

        press(4'd10);                     // CLR 取消
        if (!target_valid && entry == 9'd0)
            $display("PASS CLR取消: valid=%b entry=%0d", target_valid, entry);
        else begin $display("FAIL CLR取消: valid=%b entry=%0d", target_valid, entry); err = err + 1; end

        if (err == 0)
            $display("=== tb_target_input PASS ===");
        else
            $display("=== tb_target_input FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
