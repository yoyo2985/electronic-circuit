//------------------------------------------------------------------------------
// audio_pcm_bridge.v   ES8388(I2S, codec 主时钟) → 左右 24bit PCM 采样对
//
// 问题：ES8388 自己产生 BCLK/LRCK 喂给 FPGA，所以采样在 aud_bclk 域；而后续
//      能量/UART 都要在 50MHz 主域跑。本模块负责 I2S 接收 + 声道分离 + 跨时钟。
//
// 跨时钟方案：
//   - aud_bclk 域：按 LRC 的每个跳变开始收一个字(半周期)，MSB 先行收 WL 位。
//     收完第 2 个字(一个立体声对)后，把左右缓冲刷一遍，再隔 1 拍翻转 pair_tgl
//     （比数据晚翻转，保证缓冲已稳定）。
//   - sys_clk 域：2-FF 同步 pair_tgl，沿检测得到 pair_valid(≈fs=48k)，
//     在沿上锁存 pcm_l/pcm_r。
//
// 声道极性：aud_lrc==LRC_LEFT(默认0，I2S 标准低=左) → Left。若上板发现左右互换，
//          不要改这里，在顶层交换 pcm_l/pcm_r 即可。
// 复位：sys_rst_n 同步低有效；bclk 域内再做一次 2-FF 同步复位。
// 参数：WL 字长(默认 24)，LRC_LEFT。
//------------------------------------------------------------------------------
module audio_pcm_bridge #(
    parameter WL       = 24,          // I2S 有效字长
    parameter LRC_LEFT = 1'b0         // aud_lrc==0 视为左声道
) (
    input  wire           sys_clk,
    input  wire           sys_rst_n,

    // ES8388 / I2S（aud_bclk 域输入）
    input  wire           aud_bclk,
    input  wire           aud_lrc,
    input  wire           aud_adcdat,

    // 用户接口（sys_clk 域输出）
    output reg  [WL-1:0]  pcm_l,       // 左声道采样（跨时钟锁存）
    output reg  [WL-1:0]  pcm_r,       // 右声道采样
    output reg            pair_valid   // 每收到一个立体声对给 1 拍脉冲(≈fs)
);

    //===========================================================
    // aud_bclk 域：把 sys_rst_n 同步到 bclk 域，作该域的同步复位
    //===========================================================
    reg rst_b1, rst_b2;
    always @(posedge aud_bclk) begin
        rst_b1 <= ~sys_rst_n;
        rst_b2 <= rst_b1;
    end
    wire rst_b_n = ~rst_b2;

    //===========================================================
    // aud_bclk 域：I2S 位采样 + 声道分离
    //===========================================================
    reg        aud_lrc_d;            // LRC 打一拍，供边沿检测
    wire       lrc_edge = aud_lrc ^ aud_lrc_d;

    reg  [5:0] rx_cnt;               // 当前字已采位数(0..WL..)，到 WL 提交
    reg  [WL-1:0] wd_buf;            // 正在收的字(MSB 先行)
    reg        cur_left;             // 当前字属于左还是右(LRC 电平在沿上判)
    reg  [1:0] half;                 // 本帧内第几个字(0/1)，第 2 个字凑成立体声对
    reg  [WL-1:0] pcm_l_t;           // 左声道字暂存（bclk 域）
    reg  [WL-1:0] pcm_r_t;           // 右声道字暂存（bclk 域）
    reg        pair_tgl;             // 每对一个，翻转一次（跨域握手）
    reg        pend_tgl;             // 请求 1 拍后翻转，给缓冲留稳定时间

    always @(posedge aud_bclk) begin
        if (!rst_b_n) begin
            aud_lrc_d <= 1'b0;
            rx_cnt    <= 6'd0;
            wd_buf    <= {WL{1'b0}};
            cur_left  <= 1'b0;
            half      <= 2'd0;
            pcm_l_t   <= {WL{1'b0}};
            pcm_r_t   <= {WL{1'b0}};
            pair_tgl  <= 1'b0;
            pend_tgl  <= 1'b0;
        end else begin
            aud_lrc_d <= aud_lrc;

            if (lrc_edge) begin
                // LRC 跳变 = 新字(半周期)开始；此刻 aud_lrc 已是新电平，判声道
                rx_cnt   <= 6'd0;
                wd_buf   <= {WL{1'b0}};
                cur_left <= (aud_lrc == LRC_LEFT);
            end else if (rx_cnt <= WL) begin
                if (rx_cnt < WL)
                    wd_buf[WL-1-rx_cnt] <= aud_adcdat;   // MSB 先行

                rx_cnt <= rx_cnt + 1'b1;

                if (rx_cnt == WL) begin                  // WL 位收齐，提交本字
                    if (cur_left) pcm_l_t <= wd_buf;
                    else          pcm_r_t <= wd_buf;
                    half <= half + 1'b1;
                    if (half[0]) pend_tgl <= 1'b1;  // 第 2/4…个(奇数)字凑成立体声对
                end
            end

            // 数据提交后再翻一次握手电平，保证跨域采样时缓冲已稳定
            if (pend_tgl) begin
                pair_tgl <= ~pair_tgl;
                pend_tgl <= 1'b0;
            end
        end
    end

    //===========================================================
    // sys_clk 域：同步 pair_tgl，沿上锁存左右采样
    //===========================================================
    reg tgl_s1, tgl_s2, tgl_s3;
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            tgl_s1 <= 1'b0;
            tgl_s2 <= 1'b0;
            tgl_s3 <= 1'b0;
            pcm_l   <= {WL{1'b0}};
            pcm_r   <= {WL{1'b0}};
            pair_valid <= 1'b0;
        end else begin
            tgl_s1 <= pair_tgl;
            tgl_s2 <= tgl_s1;
            tgl_s3 <= tgl_s2;
            pair_valid <= tgl_s2 ^ tgl_s3;
            if (tgl_s2 ^ tgl_s3) begin
                pcm_l <= pcm_l_t;      // bclk 域缓冲已在翻转前稳定
                pcm_r <= pcm_r_t;
            end
        end
    end

endmodule
