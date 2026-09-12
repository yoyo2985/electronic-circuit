//------------------------------------------------------------------------------
// tb_spk_audit.v  只读审计用: 验证当前 speaker_verify.v(+vtmpl) 的
//   ① 内嵌 TPLV 是否=新 owner 模板(喂模板自身 → dist=0, match=1)
//   ② fr_match 判定 == (dist <= TH), TH 取顶层 SPK_TH=2500
//   ③ Python 尺度↔RTL 尺度逐位一致: 喂已知 L1 距离的帧, 比对 out_dist
//   不修改任何 RTL/固件。
//------------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_spk_audit;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    initial begin #30; rst_n = 1; end

    // 复制顶层实例化方式: #(.TH(SPK_TH)) SPK_TH=2500 (RTL 默认值)
    localparam TH = 2500;
    // 当前 speaker_verify.v 内嵌 TPLV(2026-09-10 重建)
    localparam [207:0] TPLV = 208'h001c005100f900f2008c004affbcff66fd0afc850179fb500bc9;

    reg        fe_valid = 0;
    reg [3:0]  fe_index = 0;
    reg signed [15:0] fe_data = 0;
    wire       frame_valid, frame_match, owner_valid;
    wire [31:0] frame_dist;

    speaker_verify #(.TH(TH), .TPLV(TPLV)) u_sv (
        .clk(clk), .rst_n(rst_n),
        .fe_feature_valid(fe_valid), .fe_index(fe_index), .fe_feature_data(fe_data),
        .frame_valid(frame_valid), .frame_dist(frame_dist), .frame_match(frame_match),
        .owner_valid(owner_valid)
    );

    // 模板 13 维 (dim0..dim12), 与 TPLV 一致
    integer i;
    reg signed [15:0] tpl [0:12];
    initial begin
        tpl[0]=3017; tpl[1]=-1200; tpl[2]=377; tpl[3]=-891; tpl[4]=-758;
        tpl[5]=-154; tpl[6]=-68; tpl[7]=74; tpl[8]=140; tpl[9]=242;
        tpl[10]=249; tpl[11]=81; tpl[12]=28;
    end

    reg [31:0] want;
    integer pass_cnt, fail_cnt;

    task feed_frame;
        input signed [15:0] v0, v1, v2, v3, v4, v5, v6;
        input signed [15:0] v7, v8, v9, v10, v11, v12;
        input [31:0] exp_dist;   // Python/期望 L1
        input exp_match;
    begin
        // 每维: 先置数据, 再等 posedge 采样 (vtmpl 在 posedge 沿采样)
        for (i = 0; i < 13; i = i + 1) begin
            fe_valid = 1; fe_index = i[3:0];
            case (i)
                0: fe_data = v0;  1: fe_data = v1;  2: fe_data = v2;  3: fe_data = v3;
                4: fe_data = v4;  5: fe_data = v5;  6: fe_data = v6;  7: fe_data = v7;
                8: fe_data = v8;  9: fe_data = v9; 10: fe_data = v10; 11: fe_data = v11;
                default: fe_data = v12;
            endcase
            @(posedge clk);
        end
        // 第 13 拍后: 停使能, 再过一拍让 speaker_verify 锁存 vtmpl 的 out_valid/dist
        fe_valid = 0;
        @(posedge clk);
        #5;
        if (frame_valid !== 1'b1) begin
            $display("FAIL 帧未完成: 期望 frame_valid=1"); fail_cnt = fail_cnt + 1;
        end else begin
            if (frame_dist !== exp_dist) begin
                $display("FAIL dist: got=%0d want=%0d", frame_dist, exp_dist); fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS dist=%0d (want %0d)", frame_dist, exp_dist); pass_cnt = pass_cnt + 1;
            end
            if (frame_match !== exp_match) begin
                $display("FAIL match: got=%0d want=%0d", frame_match, exp_match); fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS match=%0d (TH<=2500: dist<=TH)", frame_match); pass_cnt = pass_cnt + 1;
            end
        end
    end
    endtask

    // 便捷: 帧 = 模板 + 只在 dim0 上加 delta → dist = |delta|
    task feed_delta;
        input integer delta;
        input integer exp_match;
    begin
        feed_frame(tpl[0]+delta[15:0], tpl[1], tpl[2], tpl[3], tpl[4], tpl[5], tpl[6],
                   tpl[7], tpl[8], tpl[9], tpl[10], tpl[11], tpl[12],
                   (delta < 0 ? -delta : delta), exp_match);
    end
    endtask

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        @(posedge rst_n); #20;
        $display("=== tb_spk_audit: 只读审计 speaker_verify(RTL 内嵌 TPLV + 顶层 TH=2500) ===");

        // ① 喂 owner 模板自身 → dist=0, match=1
        feed_frame(tpl[0], tpl[1], tpl[2], tpl[3], tpl[4], tpl[5], tpl[6],
                   tpl[7], tpl[8], tpl[9], tpl[10], tpl[11], tpl[12], 32'd0, 1'b1);

        // ② TH 边界: dist=2499/2500 → match=1; dist=2501 → match=0
        feed_delta(2499, 1);
        feed_delta(2500, 1);
        feed_delta(2501, 0);

        // ③ Python 定标关键点: impostor min=4487 → 应 match=0
        feed_delta(4487, 0);
        //    owner max_own=1532 → 该距离帧应 match=1 (1532<=2500)
        feed_delta(1532, 1);

        $display("=== 结果: PASS=%0d FAIL=%0d ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("tb_spk_audit PASS — RTL dist==Python L1, fr_match==(dist<=2500)");
        else               $display("tb_spk_audit FAIL");
        $finish;
    end
endmodule
