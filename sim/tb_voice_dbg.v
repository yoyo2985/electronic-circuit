`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_voice_dbg.v  0xAB 语音调试帧验证(top_voice_robot, VDBG_UART=1)
//   1) 静音下自然周期: 首帧 ~200ms 到达, [AB][vad=0][mfcc=0][owner=0][cmd=0][act=0][score=0][chk] 全零
//   2) 逐字节隔离: force vad/mfcc/fr_match/owner/cmd/action/score → 对应帧字节改变
//   3) 组合帧: 全 force → [AB] 帧内容完整(端到端 mux 生效)
//   4) [AA] 主帧模块内部仍在运行(u_tele.fbyte_ok 仍在出帧, 只是 tx 被 0xAB 接管)
//   通过 force ms 逼近上报周期加速(不等待真实 200ms×N)。
//------------------------------------------------------------------------------
module tb_voice_dbg;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    reg fault_sw = 0;
    reg  aud_bclk = 0, aud_lrc = 0, aud_adcdat = 0;
    wire aud_mclk, aud_scl;
    wire aud_sda;
    assign aud_sda = 1'bz;
    wire tx;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;
    wire buzzer_out;

    // VDBG_UART=1 (显式, 默认已改为 0=生产 build), 其余与板上一致
    top_voice_robot #(.MS_DIV(4), .VEL_DEG_S(250), .TELEM_MS(30), .VDBG_UART(1)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .fault_sw(fault_sw),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .aud_mclk(aud_mclk), .aud_scl(aud_scl), .aud_sda(aud_sda),
        .tx(tx), .seg(seg), .dig_cs(dig_cs), .led(led),
        .buzzer_out(buzzer_out)
    );

    always #10 clk = ~clk;

    // ---------- 键盘模型 (静止: 不发键) ----------
    assign col = 4'hF;

    // ---------- UART RX 采样 (115200: 434 tick/bit @50MHz) ----------
    reg rx_act = 0;
    reg [3:0] rx_bit;
    reg [10:0] rx_cnt;
    reg [7:0] rx_sh;
    reg [7:0] rx_fifo [0:63];
    reg [5:0] rx_wp = 0, rx_rp = 0;
    always @(posedge clk) begin
        if (!rst_n) begin rx_act<=0; rx_bit<=0; rx_cnt<=0; rx_sh<=0; end
        else if (!rx_act) begin
            if (!tx) begin rx_act<=1; rx_bit<=0; rx_cnt<=0; end
        end else begin
            rx_cnt <= rx_cnt + 1'b1;
            if (rx_bit == 4'd0 && rx_cnt == 11'd651) begin      // 起始位中点后 1 位: bit0
                rx_sh[0] <= tx; rx_bit <= 4'd1; rx_cnt <= 0;
            end else if (rx_bit >= 4'd1 && rx_bit <= 4'd6 && rx_cnt == 11'd434) begin
                rx_sh[rx_bit] <= tx; rx_bit <= rx_bit + 1'b1; rx_cnt <= 0;
            end else if (rx_bit == 4'd7 && rx_cnt == 11'd434) begin
                rx_sh[7] <= tx; rx_bit <= 4'd8; rx_cnt <= 0;
            end else if (rx_bit == 4'd8 && rx_cnt == 11'd434) begin
                rx_act <= 0; rx_bit <= 4'd0; rx_cnt <= 0;
                rx_fifo[rx_wp] <= rx_sh; rx_wp <= (rx_wp + 1'b1) & 6'd63;
            end
        end
    end

    // ---------- 帧解析: 从 FIFO 取一帧(找到 0xAB + 7 字节 + chk 正确) ----------
    integer avail, k;
    reg [7:0] tmp [0:7];
    task get_frame(output reg got, output reg [7:0] bv, bm, bo, bc, ba, bs);
        begin
            got = 0;
            avail = (rx_wp - rx_rp) & 6'd63;
            if (avail >= 8) begin
                for (k = 0; k < 8; k = k + 1) tmp[k] = rx_fifo[(rx_rp + k) & 6'd63];
                if (tmp[0] == 8'hAB &&
                    tmp[7] == (8'hAB ^ tmp[1] ^ tmp[2] ^ tmp[3] ^ tmp[4] ^ tmp[5] ^ tmp[6])) begin
                    got = 1; bv = tmp[1]; bm = tmp[2]; bo = tmp[3];
                    bc = tmp[4]; ba = tmp[5]; bs = tmp[6];
                    rx_rp = (rx_rp + 8) & 6'd63;
                end else begin
                    rx_rp = (rx_rp + 1) & 6'd63;      // 噪声/残帧字节, 跳过
                end
            end
        end
    endtask

    integer i, err;
    reg got;
    reg [7:0] bv, bm, bo, bc, ba, bs;
    integer frames_ok, frames_bad;
    time t_first;

    // 等一帧(带超时); 返回 1 表示拿到
    task wait_frame(input [31:0] limit);
        begin
            got = 0; i = 0;
            while (!got && i < limit) begin
                @(posedge clk);
                get_frame(got, bv, bm, bo, bc, ba, bs);
                i = i + 1;
            end
            if (got) begin
                frames_ok = frames_ok + 1;
                // 校验和已由 get_frame 判定(tmp[7]==XOR 前7字节), 此处无需再验
            end else begin
                frames_bad = frames_bad + 1;
            end
        end
    endtask

    // 加速: 让 voice_dbg_rpt 每个 tick_1ms 都上报
    task arm_fast;
        begin
            force dut.g_vdbg.u_vdbg.ms = 10'd199;
        end
    endtask
    task disarm_fast;
        begin
            release dut.g_vdbg.u_vdbg.ms;
        end
    endtask

    // force 一个信号并等一帧看到它出现
    task expect_byte(input [2:0] idx, input [7:0] val, input [31:0] limit);
        reg hit;
        begin
            hit = 0; i = 0;
            while (!hit && i < limit) begin
                @(posedge clk);
                get_frame(got, bv, bm, bo, bc, ba, bs);
                if (got) begin
                    frames_ok = frames_ok + 1;
                    case (idx)
                        0: hit = (bv == val);
                        1: hit = (bm == val);
                        2: hit = (bo == val);
                        3: hit = (bc == val);
                        4: hit = (ba == val);
                        default: hit = (bs == val);
                    endcase
                end
                i = i + 1;
            end
            if (hit) $display("PASS 帧字节[%0d]=0x%02X 命中", idx, val);
            else begin $display("FAIL 帧字节[%0d] 未见 0x%02X (last bv=%02x bm=%02x bo=%02x bc=%02x ba=%02x bs=%02x)",
                                idx, val, bv, bm, bo, bc, ba, bs); err = err + 1; end
        end
    endtask

    initial begin
        err = 0; frames_ok = 0; frames_bad = 0;
        bv = 0; bm = 0; bo = 0; bc = 0; ba = 0; bs = 0;
        $display("=== tb_voice_dbg start (VDBG_UART=1) ===");
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // ---- 音频链初始化 ----
        i = 0;
        while (!dut.init_done && i < 200000) begin @(posedge clk); i = i + 1; end
        if (dut.init_done)
            $display("PASS AUD: init_done 拉高");
        else begin $display("FAIL AUD: init_done 未拉高"); err = err + 1; end

        // ---- (1) 静音自然周期首帧 (VAD off → 全零帧, ~200ms 到达) ----
        wait_frame(24000000);                      // ≤480ms
        if (got) begin
            t_first = $time;
            $display("PASS 帧: 首帧已到达 (板上周期 200ms; sim MS_DIV=4 已加速, t=%0t)", t_first);
            if (bv == 0 && bm == 0 && bo == 0 && bc == 0 && ba == 0 && bs == 0)
                $display("PASS 静音帧: 全零 (vad=%0d mfcc=%0d owner=0x%02x cmd=%0d act=%0d score=0x%02x)",
                         bv, bm, bo, bc, ba, bs);
            else begin $display("FAIL 静音帧: 应全零, 实得 bv=%0d bm=%0d bo=0x%02x bc=%0d ba=%0d bs=0x%02x",
                                bv, bm, bo, bc, ba, bs); err = err + 1; end
        end else begin
            $display("FAIL 首帧: 超时未见 [AB] 帧"); err = err + 1;
        end

        // ---- (2) 逐字节隔离 (fast reports) ----
        arm_fast;

        force dut.vad_on = 1'b1;
        expect_byte(0, 8'h01, 200000);
        release dut.vad_on;

        force dut.fe_valid = 1'b1;
        expect_byte(1, 8'h01, 200000);
        release dut.fe_valid;

        force dut.seg_done = 1'b1;
        expect_byte(2, 8'h02, 200000);             // bo bit1 = fr_any
        release dut.seg_done;

        force dut.seg_own = 1'b1;
        expect_byte(2, 8'h01, 200000);             // bo bit0 = owner
        release dut.seg_own;

        force dut.seg_cmd = 2'd3;
        force dut.dec_o_act = 3'd2;                // FWD
        expect_byte(3, 8'h03, 200000);
        expect_byte(4, 8'h02, 200000);
        release dut.seg_cmd;
        release dut.dec_o_act;

        force dut.seg_mean = 16'hABCD;
        expect_byte(5, 8'hAB, 200000);             // score = seg_mean[15:8]
        release dut.seg_mean;

        // ---- (3) 组合帧 (RIGHT: cmd=3, act=4, owner 有效, 有 MFCC) ----
        force dut.vad_on = 1'b1;
        force dut.fe_valid = 1'b1;
        force dut.seg_done = 1'b1;
        force dut.seg_own = 1'b1;
        force dut.seg_cmd = 2'd3;
        force dut.dec_o_act = 3'd4;
        force dut.seg_mean = 16'h4650;          // 0x46 高字节 → score 0x46
        expect_byte(0, 8'h01, 200000);
        expect_byte(1, 8'h01, 200000);
        expect_byte(2, 8'h03, 200000);             // fr_any|owner
        expect_byte(3, 8'h03, 200000);
        expect_byte(4, 8'h04, 200000);
        expect_byte(5, 8'h46, 200000);
        release dut.vad_on;
        release dut.fe_valid;
        release dut.seg_done;
        release dut.seg_own;
        release dut.seg_cmd;
        release dut.dec_o_act;
        release dut.seg_mean;

        disarm_fast;

        // ---- (4) [AA] 主帧模块内部仍在运行 (tx 被 0xAB 接管, 内部不出错) ----
        i = 0;
        while (!dut.u_tele.fbyte_ok && i < 3000000) begin @(posedge clk); i = i + 1; end
        if (dut.u_tele.fbyte_ok)
            $display("PASS 遥测: u_tele 内部仍在出帧 (tx 已切 0xAB, 未破坏 [AA] 逻辑)");
        else begin $display("FAIL 遥测: u_tele 内部停帧"); err = err + 1; end

        $display("汇总: 解出合法 [AB] 帧 %0d 个, 丢弃残帧 %0d 个", frames_ok, frames_bad);
        if (err == 0) $display("=== tb_voice_dbg PASS ===");
        else          $display("=== tb_voice_dbg FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
