`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_calib_smoke.v  校准固件冒烟(CALIB_UART=1)
//   ES8388 无输入(全 0)时: 音频 init 完成 → audio_calib_rpt 每 200ms 发一行
//   "P000000 L000000 R000000 V0\n"。验证 TX 确有 UART 字节输出(下降沿计数)，
//   说明数值上报链路(PLL→config→VAD→rpt)在顶层可运行。
//------------------------------------------------------------------------------
module tb_calib_smoke;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    reg fault_sw = 0;
    reg aud_bclk = 0, aud_lrc = 0, aud_adcdat = 0;
    wire aud_mclk, aud_scl, aud_sda_w;
    assign aud_sda_w = 1'bz;
    wire tx;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;
    wire buzzer_out;
    assign col = 4'hF;

    top_voice_robot #(.MS_DIV(4), .VEL_DEG_S(250), .TELEM_MS(1000),
                      .CALIB_UART(1), .INIT_MS(5)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row), .fault_sw(fault_sw),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .aud_mclk(aud_mclk), .aud_scl(aud_scl), .aud_sda(aud_sda_w),
        .tx(tx), .seg(seg), .dig_cs(dig_cs), .led(led), .buzzer_out(buzzer_out)
    );

    always #10 clk = ~clk;

    // TX 下降沿计数(每字节至少 1 个起始位下降沿)
    reg tx_d;
    integer fell;
    always @(posedge clk) begin
        tx_d <= tx;
        if (!rst_n) fell <= 0;
        else if (tx_d && !tx) fell <= fell + 1;
    end

    integer err;
    initial begin
        err = 0;
        $display("=== tb_calib_smoke start ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        // 跑足够长: init(短) + ≥1 行(27 字节 × ~4340 拍/字节)
        repeat (1500000) @(posedge clk);
        $display("calib TX 下降沿=%0d", fell);
        if (!dut.init_done) begin $display("FAIL: init_done 未拉高"); err = err + 1; end
        if (fell < 27) begin $display("FAIL: 校准行字节不足(应≥27 个起始沿)"); err = err + 1; end
        else           $display("PASS: 校准固件 TX 有 UART 输出");
        if (err == 0) $display("=== tb_calib_smoke PASS ===");
        else          $display("=== tb_calib_smoke FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
