//------------------------------------------------------------------------------
// tb_top_audio_wiretest.v   I2S 原始数据嗅探固件仿真验证
//   用 I2S 从机模型喂已知样本 L=0x123456 / R=0xFEDCBA（每 64 bclk 一对），
//   验证：bridge(WL=24) 收到正确左右值 → 先打一行 "CFG18"(仿真无codec=24NACK)，
//   再每 100ms 打 "L123456 RFEDCBA Cxxxx\n"（22 字节）。
//   同时用内部 UART 解码器把 tx 还原成字符流打印到 transcript。
//------------------------------------------------------------------------------
`timescale 1ns/1ns
module tb_top_audio_wiretest;

    reg  sys_clk = 0;
    reg  sys_rst_n = 0;
    reg  [2:0] sw = 3'b000;
    reg  aud_bclk = 0;
    reg  aud_lrc  = 0;
    reg  aud_adcdat = 0;
    wire aud_mclk;
    wire aud_scl;
    wire aud_sda;
    wire tx;
    wire [7:0] led;

    top_audio_wiretest dut (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .sw        (sw),
        .aud_bclk  (aud_bclk),
        .aud_lrc   (aud_lrc),
        .aud_adcdat(aud_adcdat),
        .aud_mclk  (aud_mclk),
        .aud_scl   (aud_scl),
        .aud_sda   (aud_sda),
        .tx        (tx),
        .led       (led)
    );

    pullup(aud_sda);

    always #10    sys_clk = ~sys_clk;      // 50MHz
    always #100   aud_bclk = ~aud_bclk;    // 5MHz（I2S 位时钟）

    //===========================================================
    // I2S 从机模型：每 64 bclk 一个立体声对
    //   bcnt 0..31 = 左槽（WS=0），32..63 = 右槽（WS=1）
    //   MSB(bit23) 在槽起点后第 2 个 bclk（对齐 bridge 的 lrc_edge 时序）
    //===========================================================
    reg [5:0] bcnt = 0;
    wire [23:0] pat_l = 24'h123456;        // +18.2% 满幅，正数
    wire [23:0] pat_r = 24'hFEDCBA;        // 负数（-0x12346）
    always @(posedge aud_bclk) begin
        if (bcnt == 6'd63) bcnt <= 6'd0;
        else               bcnt <= bcnt + 6'd1;
        if      (bcnt == 6'd31) aud_lrc <= 1'b1;
        else if (bcnt == 6'd63) aud_lrc <= 1'b0;
    end
    wire [23:0] cur = (bcnt < 6'd32) ? pat_l : pat_r;
    always @(*) begin
        if      (bcnt >= 6'd1  && bcnt <= 6'd24) aud_adcdat = cur[24-bcnt];
        else if (bcnt >= 6'd33 && bcnt <= 6'd56) aud_adcdat = cur[56-bcnt];
        else aud_adcdat = 1'b0;
    end

    //===========================================================
    // UART 解码器（115200 @50MHz，434 ticks/bit）：还原 tx → 字符
    //===========================================================
    reg tx_d, busy_rx;
    reg [12:0] tc;
    reg [3:0]  nb;
    reg [7:0]  sreg;
    reg        byte_done;
    reg [7:0]  rx_byte;
    always @(posedge sys_clk) begin
        byte_done <= 1'b0;
        if (!sys_rst_n) begin
            tx_d <= 1'b1; busy_rx <= 1'b0;
            tc <= 13'd0; nb <= 4'd0; sreg <= 8'h0; rx_byte <= 8'h0;
        end else if (!busy_rx) begin
            tx_d <= tx;
            if (!tx && tx_d) begin busy_rx <= 1'b1; tc <= 13'd216; nb <= 4'd0; end
        end else begin
            tx_d <= tx;
            if (tc == 13'd0) begin
                if (nb == 4'd0) begin
                    // 起始位中心：跳过，等 bit0 中心
                    nb <= 4'd1;
                    tc <= 13'd433;
                end else if (nb <= 4'd8) begin
                    sreg <= {tx, sreg[7:1]};           // 位中心采样，LSB 先行
                    nb <= nb + 4'd1;
                    tc <= 13'd433;
                end else begin
                    nb <= 4'd0; busy_rx <= 1'b0;
                    rx_byte <= sreg; byte_done <= 1'b1;
                end
            end else tc <= tc - 13'd1;
        end
    end

    //===========================================================
    // 字节流 → transcript；并自动判定行内容
    //   第 1 行必须为 CONF 行。仿真里没有真实 ES8388，24 笔 I2C 写
    //   全部无应答 → 应为 "CFG18\n"（0x18=24）。上板接真 codec 时为 "CFG00"。
    //   之后每行：L<6hex> R<6hex> C<4hex>\n（22 字节）
    //===========================================================
    reg [127:0] exp_head = "L123456 RFEDCBA ";   // 前 16 字符固定（I2S 从机模型喂入值）
    reg [7:0] llen;                              // 行内已收字节数
    reg       first_line;                        // 还没见过 '\n'（该查 CFG 行）
    integer   line_nr;
    reg       line_bad;
    integer   lines_ok;
    integer   cfg_lines_ok;
    initial begin
        $display("=== tb_top_audio_wiretest : 期望首行 CFG18(仿真无codec=24NACK), 然后 L123456 RFEDCBA C1E84 ===");
        line_nr = 0; lines_ok = 0; cfg_lines_ok = 0;
        line_bad = 0; llen = 0; first_line = 1;
    end
    always @(posedge sys_clk) begin
        if (byte_done) begin
            if (rx_byte == "\n") begin
                if (first_line) begin
                    if (!line_bad && llen == 8'd5) begin
                        $display("CONF OK  [%0d]  (6B)  CFG18(仿真=24NACK)", line_nr);
                        cfg_lines_ok = cfg_lines_ok + 1;
                    end else begin
                        $display("CONF BAD [%0d]  len=%0d", line_nr, llen);
                        line_bad = 1;
                    end
                    first_line = 0;
                end else begin
                    if (!line_bad && llen == 8'd21) begin
                        $display("LINE OK  [%0d]  (22B)  PASS_CHECK", line_nr);
                        lines_ok = lines_ok + 1;
                    end else begin
                        $display("LINE BAD [%0d]  len=%0d", line_nr, llen);
                        line_bad = 1;
                    end
                end
                line_nr = line_nr + 1; llen = 0; line_bad = 0;
            end else begin
                // llen = 当前字节在行内的位置
                if (first_line) begin
                    // CONF 行：位置 0..4 = "CFG18"，5='\n'
                    if (llen == 0) begin if (rx_byte != "C") begin $display("MISMATCH conf pos=0 got=%c(%02x)", rx_byte, rx_byte); line_bad = 1; end end
                    else if (llen == 1) begin if (rx_byte != "F") begin $display("MISMATCH conf pos=1 got=%c(%02x)", rx_byte, rx_byte); line_bad = 1; end end
                    else if (llen == 2) begin if (rx_byte != "G") begin $display("MISMATCH conf pos=2 got=%c(%02x)", rx_byte, rx_byte); line_bad = 1; end end
                    else if (llen == 3) begin if (rx_byte != "1") begin $display("MISMATCH conf pos=3 got=%c(%02x)", rx_byte, rx_byte); line_bad = 1; end end
                    else if (llen == 4) begin if (rx_byte != "8") begin $display("MISMATCH conf pos=4 got=%c(%02x)", rx_byte, rx_byte); line_bad = 1; end end
                end else if (llen < 8'd16) begin
                    // 位置 0..15：固定头部 "L123456 RFEDCBA "
                    if (rx_byte != exp_head[(8'd15-llen)*8 +: 8]) begin
                        $display("MISMATCH pos=%0d got=%c(%02x) exp=%c(%02x)", llen, rx_byte, rx_byte, exp_head[(8'd15-llen)*8 +: 8], exp_head[(8'd15-llen)*8 +: 8]);
                        line_bad = 1;
                    end
                end else if (llen == 8'd16) begin
                    // 位置 16：'C'
                    if (rx_byte != "C") begin
                        $display("MISMATCH pos=%0d got=%c(%02x) exp=C", llen, rx_byte, rx_byte);
                        line_bad = 1;
                    end
                end else begin
                    // 位置 17..20：C 计数 hex；位置17(MSB nibble)不得为 0
                    if (llen == 8'd17) begin
                        if (rx_byte == "0") begin
                            $display("MISMATCH pos=%0d got='0' (计数MSB=0)", llen);
                            line_bad = 1;
                        end
                    end else if (!( (rx_byte >= "0" && rx_byte <= "9") ||
                                     (rx_byte >= "A" && rx_byte <= "F") )) begin
                        $display("MISMATCH pos=%0d got=%c(%02x) (非hex)", llen, rx_byte, rx_byte);
                        line_bad = 1;
                    end
                end
                llen = llen + 1;
            end
        end
    end

    initial begin
        sys_rst_n = 0;
        repeat (5) @(posedge sys_clk);
        sys_rst_n = 1;
        // 跑 120ms：能覆盖 CONF 行(10ms) + 1 个 100ms 打印窗口
        #120_000_000;
        if (cfg_lines_ok >= 1 && lines_ok >= 1 && !line_bad) begin
            $display("==============================================");
            $display("RESULT: TEST PASS  (CONF 行 + 打印行内容正确)");
            $display("==============================================");
        end else begin
            $display("==============================================");
            $display("RESULT: TEST FAIL  (cfg_ok=%0d lines_ok=%0d)", cfg_lines_ok, lines_ok);
            $display("==============================================");
        end
        $finish;
    end

endmodule
