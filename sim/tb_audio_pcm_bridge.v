//------------------------------------------------------------------------------
// tb_audio_pcm_bridge.v
// 验证 audio_pcm_bridge：把一路 I2S 码流（ES8388 主时钟模式，LRC 低=左，MSB
// 先行，24bit）喂进模块，检查它能否把左右声道收对、且跨时钟搬到 50MHz 域。
//
// 预期波形（ModelSim）：
//   rst_n 释放后约 1~2 帧，pair_valid 每 ~12.8us 出现 1 拍（在 aud_lrc 域，
//   肉眼近似连续），pcm_l 稳定在 0x123456、pcm_r 稳定在 0xABCDEF，TEST PASS。
//   ModelSim 时间轴压缩 0.5us~100us 看 pair_valid 与 pcm_l/r。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_audio_pcm_bridge;

    localparam  WL = 24;
    localparam  LVAL = 24'h123456;    // 左声道注入值
    localparam  RVAL = 24'hABCDEF;    // 右声道注入值

    reg sys_clk   = 1'b0;
    reg sys_rst_n = 1'b0;
    reg aud_bclk  = 1'b1;
    reg aud_lrc   = 1'b0;             // 先低，模型首半周期即左声道(低)
    reg aud_adcdat = 1'b0;

    wire [WL-1:0] pcm_l, pcm_r;
    wire          pair_valid;

    audio_pcm_bridge #(.WL(WL), .LRC_LEFT(1'b0)) DUT (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .pcm_l(pcm_l), .pcm_r(pcm_r), .pair_valid(pair_valid)
    );

    // 50MHz 系统时钟
    always #10 sys_clk = ~sys_clk;

    // I2S 位时钟：200ns/周期（频率无关紧要，仅便于观察时序）
    always #100 aud_bclk = ~aud_bclk;

    //---------------------------------------------------------------
    // 码流模型：在每个 aud_bclk 下降沿推进一个 "半周期位置" pos(0..31)。
    //   pos==0  : LRC 翻转，标志一个字(半周期)开始；偶半=左(低)、奇半=右(高)
    //   pos 1..24: 送出该字数据位，值 = 数据[24-pos]，即 MSB 先出
    //   I2S 对齐：MSB 在 LRC 变沿后的第 2 个上升沿有效，等价于上述 pos=1
    //             的下降沿把 MSB 放上总线（下一个上升沿采样到）。
    //---------------------------------------------------------------
    integer nege = 0;
    integer pos;
    always @(negedge aud_bclk) begin
        nege = nege + 1;
        pos = nege % 32;
        if (pos == 0) begin
            aud_lrc <= ~aud_lrc;                      // 半周期边界
        end else if (pos <= 24) begin
            // 当前半周期是左还是右：由该半周期起始(nege-pos)的奇偶决定
            if (((nege - pos) / 32) % 2 == 0)
                aud_adcdat <= LVAL[24 - pos];          // 左：MSB 先行
            else
                aud_adcdat <= RVAL[24 - pos];          // 右
        end
    end

    //---------------------------------------------------------------
    // 检查：每个 pair_valid（跨时钟后）比较左右
    //---------------------------------------------------------------
    reg pair_d;
    integer seen = 0, good = 0, bad = 0, total = 0;

    always @(posedge sys_clk) begin
        pair_d <= pair_valid;
        if (!sys_rst_n) begin
            seen <= 0; good <= 0; bad <= 0; total <= 0;
        end else if (pair_d) begin
            seen <= seen + 1;
            if (seen >= 3) begin      // 跳过上电头 2 帧暂态，从稳定处开始判
                total <= total + 1;
                if (pcm_l == LVAL && pcm_r == RVAL)
                    good <= good + 1;
                else begin
                    bad <= bad + 1;
                    $display("[ERR] frame: pcm_l=%06h pcm_r=%06h (want %06h/%06h)",
                             pcm_l, pcm_r, LVAL, RVAL);
                end
            end
        end
    end

    //---------------------------------------------------------------
    // 主测试
    //---------------------------------------------------------------
    initial begin
        // 复位
        sys_rst_n = 1'b0;
        repeat(10) @(posedge sys_clk);
        sys_rst_n = 1'b1;

        // 跑若干帧（一帧 = 64 个 bclk ≈ 12.8us）
        #400000;

        if (total >= 3 && bad == 0) begin
            $display("TEST PASS : %0d frames, all L=0x%06h R=0x%06h", total, LVAL, RVAL);
        end else begin
            $display("TEST FAIL : total=%0d good=%0d bad=%0d", total, good, bad);
        end
        $finish;
    end

    // 超时保护
    initial #500000 begin
        $display("TEST TIMEOUT");
        $finish;
    end

endmodule
