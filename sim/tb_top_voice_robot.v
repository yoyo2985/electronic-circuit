`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_top_voice_robot.v  Phase 1 集成验证(top_voice_robot)
//   1) 语音缝四命令:  FORWARD(0→90) / RIGHT(→180) / LEFT(→0) / STOP(保持HOLD)
//      —— 均走 state_machine→trajectory→PID→virtual_motor，与 V1 同一条链
//   2) 遥测帧在线校验: 捕获 [AA][state][tgt][pos][chk]，state≤4 且校验和正确
//   3) V1 键盘回归:   9,0→ENTER→MOVE→HOLD(90)→SW2故障→CLR→IDLE
//                     证明键盘路径在统一 seam 下与 top_system 行为一致
//------------------------------------------------------------------------------
module tb_top_voice_robot;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] col;
    wire [3:0] row;
    reg fault_sw = 0;
    // ES8388 接口: 无音频源时全部拉低/z, 只验证接线与运动不受影响
    reg  aud_bclk = 0, aud_lrc = 0, aud_adcdat = 0;
    wire aud_mclk, aud_scl;
    wire aud_sda;
    assign aud_sda = 1'bz;
    wire tx;
    wire [7:0] seg;
    wire [3:0] dig_cs;
    wire [7:0] led;
    wire buzzer_out;

    // VDBG_UART=0: 本 tb 验证默认 build([AA] 遥测路径不受 0xAB 调试帧影响)。
    // 0xAB 帧内容由 tb_voice_dbg.v 单独验证(VDBG_UART=1)。
    top_voice_robot #(.MS_DIV(4), .VEL_DEG_S(250), .TELEM_MS(30), .VDBG_UART(0)) dut (
        .clk(clk), .rst_n(rst_n), .col(col), .row(row),
        .fault_sw(fault_sw),
        .aud_bclk(aud_bclk), .aud_lrc(aud_lrc), .aud_adcdat(aud_adcdat),
        .aud_mclk(aud_mclk), .aud_scl(aud_scl), .aud_sda(aud_sda),
        .tx(tx), .seg(seg), .dig_cs(dig_cs), .led(led),
        .buzzer_out(buzzer_out)
    );

    always #10 clk = ~clk;

    // ---------- 键盘模型 (与 tb_top_system 一致) ----------
    reg press = 0;
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

    task automatic press_label(input integer k);
        begin
            pr = k >> 2; pc = k & 2'd3;
            press = 1'b1;
            i = 0; while (!dut.key_event && i < 20000) begin @(posedge clk); i = i + 1; end
            press = 1'b0;
            i = 0; while (dut.key_event && i < 20000) begin @(posedge clk); i = i + 1; end
            repeat (5) @(posedge clk);
        end
    endtask

    // ---------- 语音命令注入 (force 顶层语音缝；板上默认 0) ----------
    reg [2:0] va;
    task automatic issue_voice(input [2:0] a);
        begin
            va = a;                       // force 需要模块级变量作为数据源
            force dut.v_act_valid = 1'b1;
            force dut.v_act = va;
            repeat (3) @(posedge clk);
            release dut.v_act_valid;
            release dut.v_act;
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic wait_state(input [2:0] s, input [31:0] limit);
        begin
            i = 0;
            while (dut.u_fsm.state != s && i < limit) begin @(posedge clk); i = i + 1; end
        end
    endtask

    // 等待到位: state==HOLD 且 pos 收敛到 [g-2,g+2]
    task automatic wait_settle(input [9:0] g, input [31:0] limit);
        reg hit;
        begin
            hit = 0; i = 0;
            while (!hit && i < limit) begin
                @(posedge clk);
                if (dut.u_fsm.state == 3'd3 &&
                    dut.pos >= (g - 2) && dut.pos <= (g + 2)) hit = 1;
                i = i + 1;
            end
        end
    endtask

    // ---------- 遥测帧在线捕获/校验 (读到 tele_ev=1 后取 tele_*) ----------
    // uart_telemetry 在 fbyte_ok 同一拍才把 fbyte 置为当前字节(NBA)，故延后 1 拍采样。
    // 注: sim 中 MOVE 段短于单帧 UART 时长，state=2 的帧能否命中是时序巧合，故不强求；
    //     真正证据 = 帧校验和正确 + state/target/pos 自洽。板级 MOVE 长达数秒必出多帧。
    reg ok_d = 0;
    reg caph = 0; integer capi;
    reg [7:0] cap0, cap1, cap2;
    reg tele_ev = 0, tele_good = 0;
    reg [7:0] tele_state, tele_tgt, tele_pos;
    integer good_count = 0;
    always @(posedge clk) ok_d <= dut.u_tele.fbyte_ok;
    always @(posedge clk) begin
        if (!rst_n) begin caph <= 0; capi <= 0; tele_ev <= 0; end
        else begin
            tele_ev <= 0;
            if (ok_d) begin
                if (dut.u_tele.fbyte == 8'hAA) begin caph <= 1; capi <= 0; end
                else if (caph) begin
                    if (capi < 3) begin
                        case (capi)
                            0: cap0 <= dut.u_tele.fbyte;
                            1: cap1 <= dut.u_tele.fbyte;
                            default: cap2 <= dut.u_tele.fbyte;
                        endcase
                        capi <= capi + 1;
                    end else begin              // capi==3 → 本字节即 chk
                        caph <= 0; capi <= 0;
                        tele_good <= (dut.u_tele.fbyte == (8'hAA ^ cap0 ^ cap1 ^ cap2));
                        tele_state <= cap0; tele_tgt <= cap1; tele_pos <= cap2;
                        tele_ev <= 1;
                    end
                end
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) good_count <= 0;
        else if (tele_ev && tele_good && tele_state <= 8'd4) good_count <= good_count + 1;
    end

    reg seen_good_frame;
    task automatic expect_any_good_frame;
        begin
            seen_good_frame = 0;
            i = 0;
            while (!seen_good_frame && i < 400000) begin
                @(posedge clk);
                if (tele_ev && tele_good && tele_state <= 8'd4) seen_good_frame = 1;
                i = i + 1;
            end
            if (seen_good_frame) $display("PASS 遥测: 捕获合法 [AA] 帧");
            else begin $display("FAIL 遥测: 未见合法 [AA] 帧"); err = err + 1; end
        end
    endtask

    initial begin
        err = 0;
        $display("=== tb_top_voice_robot start ===");
        press = 0; pr = 0; pc = 0; caph = 0; capi = 0;
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // ---- Phase2: ES8388 链上电复位/初始化自动完成(不影响运动) ----
        i = 0;
        while (!dut.init_done && i < 80000) begin @(posedge clk); i = i + 1; end
        if (dut.init_done)
            $display("PASS AUD: init_done 拉高 (PLL lock→I2C 配置→200ms 延时链 OK)");
        else begin $display("FAIL AUD: init_done 未拉高"); err = err + 1; end

        // ---- 语音命令：FORWARD (0→90) ----
        issue_voice(3'd2);                       // FORWARD
        wait_state(3'd2, 10000);
        if (dut.u_fsm.state == 3'd2) $display("PASS V: FORWARD → MOVE");
        else begin $display("FAIL V: FORWARD 未进 MOVE state=%0d", dut.u_fsm.state); err = err + 1; end
        expect_any_good_frame;
        wait_settle(10'd90, 400000);
        if (dut.u_fsm.state == 3'd3 && dut.pos >= 88 && dut.pos <= 92)
            $display("PASS V: FORWARD 收敛 pos=%0d", dut.pos);
        else begin $display("FAIL V: FORWARD 未收敛 state=%0d pos=%0d", dut.u_fsm.state, dut.pos); err = err + 1; end

        // ---- 语音命令：RIGHT (90→180) ----
        issue_voice(3'd4);
        wait_state(3'd2, 10000);
        wait_settle(10'd180, 500000);
        if (dut.u_fsm.state == 3'd3 && dut.pos >= 178 && dut.pos <= 180)
            $display("PASS V: RIGHT 收敛 pos=%0d", dut.pos);
        else begin $display("FAIL V: RIGHT 未收敛 state=%0d pos=%0d", dut.u_fsm.state, dut.pos); err = err + 1; end

        // ---- 语音命令：LEFT (180→0) ----
        issue_voice(3'd3);
        wait_state(3'd2, 10000);
        wait_settle(10'd0, 500000);
        if (dut.u_fsm.state == 3'd3 && dut.pos <= 2)
            $display("PASS V: LEFT 收敛 pos=%0d", dut.pos);
        else begin $display("FAIL V: LEFT 未收敛 state=%0d pos=%0d", dut.u_fsm.state, dut.pos); err = err + 1; end

        // ---- 语音命令：STOP (已 HOLD@0，应不发起新运动) ----
        issue_voice(3'd0);
        repeat (2000) @(posedge clk);           // 观察一段
        if (dut.u_fsm.state == 3'd3 && dut.pos <= 2)
            $display("PASS V: STOP 保持 HOLD pos=%0d (无新运动)", dut.pos);
        else begin $display("FAIL V: STOP 后 state=%0d pos=%0d 应保持", dut.u_fsm.state, dut.pos); err = err + 1; end

        // ---- V1 键盘回归: 输入 90 → ENTER → MOVE → HOLD ----
        press_label(9);
        press_label(0);
        if (dut.u_ti.entry == 9'd90)
            $display("PASS KBD: 输入 90");
        else begin $display("FAIL KBD: entry=%0d", dut.u_ti.entry); err = err + 1; end
        press_label(11);                        // ENTER+GO (键盘接管, 清除语音 valid)
        wait_state(3'd2, 10000);
        if (dut.u_fsm.state == 3'd2) $display("PASS KBD: 键盘 ENTER → MOVE (语音被接管)");
        else begin $display("FAIL KBD: 未进 MOVE state=%0d", dut.u_fsm.state); err = err + 1; end
        wait_settle(10'd90, 400000);
        if (dut.u_fsm.state == 3'd3 && dut.pos >= 88 && dut.pos <= 92)
            $display("PASS KBD: 键盘回归收敛 pos=%0d", dut.pos);
        else begin $display("FAIL KBD: 未收敛 state=%0d pos=%0d", dut.u_fsm.state, dut.pos); err = err + 1; end

        // ---- V1 强故障 + CLR ----
        fault_sw = 1;
        repeat (3) @(posedge clk);
        if (dut.u_fsm.state == 3'd4)
            $display("PASS KBD: 强故障→FAULT");
        else begin $display("FAIL KBD: 未进 FAULT state=%0d", dut.u_fsm.state); err = err + 1; end
        fault_sw = 0;
        press_label(10);
        repeat (5) @(posedge clk);
        if (dut.u_fsm.state == 3'd0)
            $display("PASS KBD: CLR→IDLE");
        else begin $display("FAIL KBD: 未回 IDLE state=%0d", dut.u_fsm.state); err = err + 1; end

        // ---- 遥测帧正确性抽查: 全 run 至少解出 1 帧合法 [AA] ----
        $display("遥测: 解出合法 [AA] 帧数 = %0d (末帧 state=%0d tgt=%0d pos=%0d)",
                 good_count, tele_state, tele_tgt, tele_pos);
        if (good_count < 1) begin
            $display("FAIL 遥测: 整个 run 未见合法 [AA] 帧"); err = err + 1;
        end

        if (err == 0) $display("=== tb_top_voice_robot PASS ===");
        else          $display("=== tb_top_voice_robot FAIL (err=%0d) ===", err);
        $finish;
    end
endmodule
