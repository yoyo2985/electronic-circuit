`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_seg.v   top_seg 顶层接线 + BCD 计数器自检
//   参数缩小：MS_DIV=5(每 5 周期 1 个 tick_1ms)，INC_MS=4(每 4ms 加 1)
//   即：每 5 周期 1 个 tick_1ms，每 4 个 tick_1ms => 20 周期加 1。
//------------------------------------------------------------------------------
module tb_top_seg;
    reg clk = 0;
    reg rst_n = 0;
    wire [7:0] seg;
    wire [3:0] dig_cs;

    top_seg #(.MS_DIV(5), .INC_MS(4)) dut (
        .clk(clk), .rst_n(rst_n), .seg(seg), .dig_cs(dig_cs)
    );

    always #10 clk = ~clk;   // 50 MHz

    // 期望的 BCD 值（与 RTL 相同的进位逻辑，逐拍对齐）
    reg [3:0] e0 = 4'd0, e1 = 4'd0, e2 = 4'd0, e3 = 4'd0;
    wire [15:0] expect = {e3, e2, e1, e0};

    always @(posedge clk) begin
        if (!rst_n) begin
            e0 <= 4'd0; e1 <= 4'd0; e2 <= 4'd0; e3 <= 4'd0;
        end else if (dut.tick_inc) begin
            if (e0 == 4'd9) begin e0 <= 4'd0;
                if (e1 == 4'd9) begin e1 <= 4'd0;
                    if (e2 == 4'd9) begin e2 <= 4'd0;
                        e3 <= (e3 == 4'd9) ? 4'd0 : e3 + 4'd1;
                    end else e2 <= e2 + 4'd1;
                end else e1 <= e1 + 4'd1;
            end else e0 <= e0 + 4'd1;
        end
    end

    integer i, err;
    initial begin
        err = 0;
        $display("=== tb_top_seg start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;

        for (i = 0; i < 400; i = i + 1) begin
            @(posedge clk);
            if (i % 20 == 0)
                $display("cyc=%0d bcd=%h seg=%b dig_cs=%b", i, dut.bcd_data, seg, dig_cs);
        end

        // 校验 bcd 计数值
        if (dut.bcd_data === expect)
            $display("PASS: bcd_data=%h 与期望一致", dut.bcd_data);
        else begin
            $display("FAIL: bcd_data=%h 期望=%h", dut.bcd_data, expect);
            err = err + 1;
        end

        // 校验位选 dig_cs 在 4 个低有效位之间轮转
        if (dut.dig_cs === 4'b1110 || dut.dig_cs === 4'b1101 ||
            dut.dig_cs === 4'b1011 || dut.dig_cs === 4'b0111)
            $display("PASS: dig_cs=%b 位选正常", dut.dig_cs);
        else begin
            $display("FAIL: dig_cs=%b 非法位选", dut.dig_cs);
            err = err + 1;
        end

        if (err == 0)
            $display("=== tb_top_seg PASS ===");
        else
            $display("=== tb_top_seg FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
