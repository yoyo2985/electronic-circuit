`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_key.v   顶层 top_key 接线验证：按键 → 十进制 BCD 送显示
//   按键(3,0)=键号12 → 期望 bcd=8'h12(两位“12”)、blank=4'b1100；
//   再按(1,1)=键号5  → 期望 bcd=8'h05、blank=4'b1110(十位消隐)。
//------------------------------------------------------------------------------
module tb_top_key;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;

    // 仿真参数缩小：MS_DIV=8、DEBOUNCE_N=2
    top_key #(.MS_DIV(8), .DEBOUNCE_N(2)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .seg(seg), .dig_cs(dig_cs), .led(led)
    );

    always #10 clk = ~clk;   // 50 MHz

    // ---- 键盘行为模型 ----
    reg press;
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
    initial begin
        err = 0;
        $display("=== tb_top_key start ===");
        press = 0; pr = 0; pc = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (30) @(posedge clk);

        // ---- 按键号 12：(row=3,col=0) ----
        pr = 3; pc = 0; press = 1;
        i = 0;
        while (!dut.key_event && i < 800) begin @(posedge clk); i = i + 1; end
        if (dut.key_idx == 4'd12 && dut.bcd == 8'h12 && dut.blank == 4'b1100)
            $display("PASS 键12: key_idx=%0d bcd=%h blank=%b", dut.key_idx, dut.bcd, dut.blank);
        else begin
            $display("FAIL 键12: key_idx=%0d bcd=%h blank=%b", dut.key_idx, dut.bcd, dut.blank);
            err = err + 1;
        end
        press = 0;
        repeat (40) @(posedge clk);

        // ---- 按键号 5：(row=1,col=1) ----
        pr = 1; pc = 1; press = 1;
        i = 0;
        while (!dut.key_event && i < 800) begin @(posedge clk); i = i + 1; end
        if (dut.key_idx == 4'd5 && dut.bcd == 8'h05 && dut.blank == 4'b1110)
            $display("PASS 键5: key_idx=%0d bcd=%h blank=%b", dut.key_idx, dut.bcd, dut.blank);
        else begin
            $display("FAIL 键5: key_idx=%0d bcd=%h blank=%b", dut.key_idx, dut.bcd, dut.blank);
            err = err + 1;
        end
        press = 0;

        if (err == 0)
            $display("=== tb_top_key PASS ===");
        else
            $display("=== tb_top_key FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
