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
// 判读：
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
    output wire aud_scl,       // R12
    inout  wire aud_sda,       // R9
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

    assign led[0] = a_bclk;
    assign led[1] = a_ws;
    assign led[2] = a_do;
    assign led[3] = rst_i;          // 常亮=程序在跑且 PLL 已锁、复位已放开
    assign led[4] = ~cfg_ack;       // 亮=ES8388 应答了 I2C(供电+地址+SDA/SCL 都对)
    assign led[5] = tone;           // E13：1kHz 测试音输出(灌咪头座用)
    assign led[7:6] = 2'b0;

endmodule
