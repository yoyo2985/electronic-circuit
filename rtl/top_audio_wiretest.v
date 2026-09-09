//------------------------------------------------------------------------------
// top_audio_wiretest.v   ES8388 接线自检（最简单、专查接线/供电/codec 是否起来）
//
// 它做的事极少：
//   1) PLL 从 50MHz 出 12.3MHz → aud_mclk 送给 ES8388
//   2) I2C 配置 ES8388（es8388_config，官方寄存器表）
//   3) 模块若被配置好且供电正常，会自己从 MCLK 生成 BCLK/WS 并回送 FPGA；
//      配置好后才可能在 SDOUT 上有音频数据。
//   4) 用 3 个 LED 显示三根"模块→FPGA"线的活动：
//        led0 = BCK  (aud_bclk, M6) 有翻转
//        led1 = WS   (aud_lrc , M7) 有翻转
//        led2 = DO   (aud_adcdat,R14)有翻转（静音时可能不亮，说话才亮）
//        led3 = 常亮：程序在跑、PLL 锁、复位已放开
//        led4 = 亮：ES8388 在 I2C 上应答了（供电+地址+SDA/SCL 都对）
//   5) I2S 原始数据嗅探：每 100ms 经 UART(115200,D12) 发一行
//        "L<6hex> R<6hex> C<4hex>\n"
//        L/R = 窗口内第一个立体声对的 24bit 原始 PCM（补码 hex）
//        C   = 窗口内样本对数（48k 时应≈4800）
//      判读：
//        · C≈4800 且 L/R 随说话变化 → 整条采集链已通，之前的问题在能量统计环节
//        · C≈4800 但 L/R 恒 0x000000 → DO 上有时钟但无 ADC 数据（codec 模拟端/咪头）
//        · C 乱/≈0                  → BCK/WS/DO 对齐或接线问题
// 判读（LED）：
//   · led3 灭 → 程序没在跑/复位没放开（查 SW0、下载）
//   · led4 灭 → ES8388 不应答：供电或 I2C 地址或 SCL/SDA 线问题
//   · led4 亮 led0 灭 → 地址/供电都对但没出时钟：查 MCK/主从
//   · led0 亮 → codec 已起来(供电+MCK+配置+BCK线都对)
//   · led0亮 led1 灭 → WS 那根线(M7)有问题
//   · led0/1亮 led2 灭 → DO 那根线(R14)或咪头问题（说话看看）
//   · 说话 led2 闪 → 整条采集链已通！
//------------------------------------------------------------------------------
module top_audio_wiretest (
    input  wire sys_clk,       // R7
    input  wire sys_rst_n,     // A9 (SW0 拨上=运行)
    input  wire [2:0] sw,      // SW1/2/3(A10/B10/A11)：ADC 输入选择扫描 inp_sel
    input  wire aud_bclk,      // M6   codec→FPGA
    input  wire aud_lrc,       // M7
    input  wire aud_adcdat,    // R14
    output wire aud_mclk,      // N5
    output wire aud_dacdat,    // P6   FPGA→codec DIN（本自检构建：计数斜坡）
    output wire aud_scl,       // R12
    inout  wire aud_sda,       // R9
    output wire tx,            // UART 115200, D12（I2S 原始数据嗅探打印）
    output wire [7:0] led      // led[4:0] 含义见注释
);

    reg  [7:0] rst_cnt = 8'd0;
    always @(posedge sys_clk)
        rst_cnt <= rst_cnt[7] ? rst_cnt : rst_cnt + 1'b1;

    wire locked, clk0_unused;
    clk_wiz_0 u_pll (
        .refclk  (sys_clk),
        .reset   (~rst_cnt[7]),
        .stdby   (1'b0),
        .extlock (locked),
        .clk0_out(clk0_unused),
        .clk1_out(aud_mclk)
    );
    wire rst_i = sys_rst_n & locked;

    wire cfg_ack;                    // 1=ES8388 在 I2C 器件地址上无应答

    es8388_config u_cfg (
        .clk    (sys_clk),
        .rst_n  (rst_i),
        .volume (2'b01),
        .aud_scl(aud_scl),
        .aud_sda(aud_sda),
        .ack_err(cfg_ack),
        .inp_sel(sw)
    );

    wire tick_1ms;
    clock_enable #(.MS_DIV(50000)) u_ce (
        .clk(sys_clk), .rst_n(rst_i), .tick_1ms(tick_1ms)
    );

    wire a_bclk, a_ws, a_do;
    sig_activity u_ab (.clk(sys_clk), .rst_n(rst_i), .tick_1ms(tick_1ms), .sig(aud_bclk),  .on(a_bclk));
    sig_activity u_aws(.clk(sys_clk), .rst_n(rst_i), .tick_1ms(tick_1ms), .sig(aud_lrc),   .on(a_ws));
    sig_activity u_ado(.clk(sys_clk), .rst_n(rst_i), .tick_1ms(tick_1ms), .sig(aud_adcdat),.on(a_do));

    // 1kHz 测试音：从 E13(LED5) 飞线灌进咪头座，验证 ADC 模拟通路
    reg [14:0] tc;
    reg tone;
    always @(posedge sys_clk) begin
        if (!rst_i) begin tc <= 15'd0; tone <= 1'b0; end
        else begin
            tc <= tc + 1'b1;
            if (tc == 15'd24999) begin tc <= 15'd0; tone <= ~tone; end
        end
    end

    //==========================================================================
    // I2S 原始数据嗅探：把 DO(R14) 上采到的 24bit PCM 直接打上串口
    //   ⚠ 布线铁律（2026-09-09 实测踩坑）：R14(FPGA adcdat) ↔ 模块 I2S_DI ↔
    //     ES8388 ASDOUT(ADC 输出)；P6(FPGA dacdat) ↔ 模块 I2S_DO ↔ DSDIN(DAC 输入)。
    //     模块 DI/DO 命名站在 FPGA 侧。散线版模块曾把 DI/DO 接反 → R14 收到悬空
    //     DAC 线恒 0xFFFFFF。换正后 R14 才收到 codec 真实 ADC 数据。
    //   上电后先发一行配置健康：CFG<2hex>\n（<2hex>=I2C 无应答传输次数）
    //     CFG00 → 24 笔配置写全部应答（codec 供电/地址0x11/SDA/SCL 正常）
    //     CFG..>00 → 有 NACK：查 ES8388 供电、I2C 地址、SDA/SCL 线
    //   然后每 100ms 发一行嗅探：L<6hex> R<6hex> C<4hex>\n
    //     L/R = 窗口内第一个立体声对的原始 24bit 采样(signed 补码)
    //     C   = 窗口内样本对计数（48k 时应≈4800）
    //   判读：
    //     · CFG00 C≈4800 且 L/R 随说话变化 → 整条采集链已通
    //     · CFG00 C≈4800 但 L/R 恒 0xFFFFFF(=-1LSB 静音) → codec 配置到位但
    //       ADC 模拟端没吃到咪头信号：查咪头接线/偏置/输入选择(sw)/差分模式
    //     · CFG00 C≈4800 但 L/R 恒 0x000000 → DO 有信号但 ADC 出数字 0
    //     · CFG 非 00 → 配置都没写进去，先修 I2C 链路再看模拟端
    //     · C 乱/≈0 → BCK/WS/DO 对齐或接线问题
    //==========================================================================

    // ---- 配置健康：复位后 ~10ms 窗口内统计 I2C 无应答次数 ----
    reg  [15:0] cfg_ms;
    reg         cfg_window;
    reg         cfg_win_end;      // 窗口结束脉冲（1 拍）
    reg  [7:0]  cfg_nack;         // 窗口内 NACK 次数
    reg         ack_d;
    wire        ack_rise = cfg_ack & ~ack_d;
    always @(posedge sys_clk) begin
        ack_d <= cfg_ack;
        if (!rst_i) begin
            cfg_ms <= 16'd0; cfg_window <= 1'b1;
            cfg_nack <= 8'd0; cfg_win_end <= 1'b0;
        end else begin
            cfg_win_end <= 1'b0;
            if (tick_1ms) begin
                if (cfg_ms == 16'd9) begin
                    cfg_ms <= 16'd0; cfg_window <= 1'b0;
                    cfg_win_end <= 1'b1;
                end else cfg_ms <= cfg_ms + 1'b1;
            end
            if (cfg_window && ack_rise) cfg_nack <= cfg_nack + 1'b1;
        end
    end

    //==========================================================================
    // DAC 通路自检已完成（计数斜坡验证布线 → DI/DO 换正 → LED2 亮收工）。
    // 现在 P6(aud_dacdat/DSDIN) 拉低 → DAC 静音，避免自检锯齿从 LOUT/ROUT
    // 喇叭回灌进咪头干扰 ADC 读数。要再验 DAC 通路可查 git 历史里的斜坡版。
    //==========================================================================
    assign aud_dacdat = 1'b0;

    // ---- I2S 采集：桥接器收真实 DO(R14)=codec ASDOUT 的 24bit 麦克风数据 ----
    //     （DI/DO 散线已按原理图换正：R14↔I2S_DI=ASDOUT、P6↔I2S_DO=DSDIN）
    wire [23:0] sp_l, sp_r;
    wire        sp_v;
    audio_pcm_bridge u_br (
        .sys_clk   (sys_clk),
        .sys_rst_n (rst_i),
        .aud_bclk  (aud_bclk),
        .aud_lrc   (aud_lrc),
        .aud_adcdat(aud_adcdat),
        .pcm_l     (sp_l),
        .pcm_r     (sp_r),
        .pair_valid(sp_v)
    );

    reg [23:0] sp_l_snap, sp_r_snap;   // 窗口内第一个样本对
    reg [15:0] sp_cnt;                 // 窗口内样本对计数（连续计）
    reg [15:0] sp_cnt_snap;            // 窗口边界锁存，显示用（避免清零/显示打架）
    reg [6:0]  s_ms;                   // 100ms 分频
    reg        sp_hb;                  // 该发一行了（1 拍脉冲）
    always @(posedge sys_clk) begin
        if (!rst_i) begin
            sp_l_snap <= 24'd0; sp_r_snap <= 24'd0;
            sp_cnt <= 16'd0; sp_cnt_snap <= 16'd0;
            s_ms <= 7'd0; sp_hb <= 1'b0;
        end else begin
            sp_hb <= 1'b0;
            if (sp_v) begin
                if (sp_cnt == 16'd0) begin sp_l_snap <= sp_l; sp_r_snap <= sp_r; end
                sp_cnt <= sp_cnt + 1'b1;
            end
            if (tick_1ms) begin
                if (s_ms == 7'd99) begin
                    s_ms <= 7'd0;
                    sp_hb <= 1'b1;
                    sp_cnt_snap <= sp_cnt;       // 锁存本窗口样本对数
                    sp_cnt <= 16'd0;             // 开新窗口
                end else s_ms <= s_ms + 1'b1;
            end
        end
    end

    wire tx_busy;
    reg  send;
    reg  [7:0] byte_out;
    uart_tx #(.BAUD_TICKS(434)) u_tx (
        .clk(sys_clk), .rst_n(rst_i), .send(send),
        .tx_data(byte_out), .tx(tx), .busy(tx_busy)
    );

    reg line_kind;   // 1=CONF 行(6字节) 0=嗅探行(22字节)
    reg [4:0] bi;
    reg [3:0] nib;
    always @(*) begin
        if (line_kind) begin
            case (bi)
                5'd0 : byte_out = "C";
                5'd1 : byte_out = "F";
                5'd2 : byte_out = "G";
                5'd5 : byte_out = "\n";
                default: begin
                    nib = (bi==5'd3) ? cfg_nack[7:4] : (bi==5'd4) ? cfg_nack[3:0] : 4'd0;
                    byte_out = (nib < 4'd10) ? (8'h30 + nib) : (8'h37 + nib);
                end
            endcase
        end else begin
            case (bi)
                5'd0 : byte_out = "L";
                5'd7 : byte_out = " ";
                5'd8 : byte_out = "R";
                5'd15: byte_out = " ";
                5'd16: byte_out = "C";
                5'd21: byte_out = "\n";
                default: begin
                    if      (bi >= 1 && bi <= 6)  nib = sp_l_snap[(6-bi)*4 +: 4];
                    else if (bi >= 9 && bi <= 14) nib = sp_r_snap[(14-bi)*4 +: 4];
                    else if (bi >= 17 && bi <= 20)nib = sp_cnt_snap[(20-bi)*4 +: 4];
                    else nib = 4'd0;
                    byte_out = (nib < 4'd10) ? (8'h30 + nib) : (8'h37 + nib);
                end
            endcase
        end
    end

    reg framing;
    reg sent;
    reg cfg_sent;   // CONF 行已发过
    always @(posedge sys_clk) begin
        send <= 1'b0;
        if (!rst_i) begin
            bi <= 5'd0; framing <= 1'b0; sent <= 1'b0;
            line_kind <= 1'b0; cfg_sent <= 1'b0;
        end else begin
            if (!framing) begin
                sent <= 1'b0;
                if (cfg_win_end && !cfg_sent) begin
                    cfg_sent <= 1'b1;
                    line_kind <= 1'b1;             // 先发一行 CONF
                    framing <= 1'b1; bi <= 5'd0;
                end else if (sp_hb) begin
                    line_kind <= 1'b0;
                    framing <= 1'b1; bi <= 5'd0;
                end
            end else if (!sent) begin
                if (!tx_busy) begin send <= 1'b1; sent <= 1'b1; end
            end else begin
                if (!tx_busy) begin
                    sent <= 1'b0;
                    if (bi == (line_kind ? 5'd5 : 5'd21)) framing <= 1'b0;
                    else             bi <= bi + 1'b1;
                end
            end
        end
    end

    assign led[0] = a_bclk;
    assign led[1] = a_ws;
    assign led[2] = a_do;
    assign led[3] = rst_i;          // 常亮=程序在跑且 PLL 已锁、复位已放开
    assign led[4] = ~cfg_ack;       // 亮=ES8388 应答了 I2C(供电+地址+SDA/SCL 都对)
    assign led[5] = tone;           // E13：1kHz 测试音输出(灌咪头座用)
    assign led[7:6] = 2'b0;

endmodule
