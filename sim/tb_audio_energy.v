//------------------------------------------------------------------------------
// tb_audio_energy.v   验证窗口平均 |x|：
//   每 64 拍给 1 个 sample_ok，窗口 WIN=32 → 每窗 2048 拍。
//   窗0: 注入 L=+1000 R=-500  → 期望 avg_l=1000 avg_r=500
//   窗1: 注入 L=-2000 R=+1234 → 期望 avg_l=2000 avg_r=1234
//   交替 4 窗，全对即 PASS。
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_audio_energy;

    localparam AW = 24;
    reg clk = 1'b0, rst_n = 1'b0;
    reg sample_ok = 1'b0;
    reg [AW-1:0] pl = 0, pr = 0;
    wire [AW:0] avg_l, avg_r;
    wire win_done;

    audio_energy #(.AW(AW), .WIN_LOG2(5)) DUT (
        .clk(clk), .rst_n(rst_n), .sample_ok(sample_ok),
        .pcm_l(pl), .pcm_r(pr),
        .avg_l(avg_l), .avg_r(avg_r), .win_done(win_done)
    );

    always #10 clk = ~clk;

    // sample_ok：每 64 拍一次
    reg [7:0] scnt;
    always @(posedge clk) begin
        if (!rst_n) begin scnt <= 0; sample_ok <= 1'b0; end
        else begin
            sample_ok <= 1'b0;
            if (scnt == 8'd63) begin sample_ok <= 1'b1; scnt <= 8'd0; end
            else scnt <= scnt + 1'b1;
        end
    end

    // 窗口边界后切下一窗注入值；active 记录当前窗号
    reg active;
    reg wd1;
    integer bad = 0, wins = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            active <= 1'b0; wd1 <= 1'b0; bad <= 0; wins <= 0;
        end else begin
            wd1 <= win_done;
            if (wd1) begin
                // 上一窗结束：avg 已更新，比对
                wins <= wins + 1;
                case (active)
                    1'b0: begin
                        if (avg_l != 1000 || avg_r != 500) begin
                            bad <= bad + 1;
                            $display("[ERR] win0 avg_l=%0d avg_r=%0d want 1000/500", avg_l, avg_r);
                        end
                    end
                    default: begin
                        if (avg_l != 2000 || avg_r != 1234) begin
                            bad <= bad + 1;
                            $display("[ERR] win1 avg_l=%0d avg_r=%0d want 2000/1234", avg_l, avg_r);
                        end
                    end
                endcase
                // 切换到下一窗注入值（负值自动转补码）
                active <= ~active;
                if (active == 1'b0) begin
                    pl <= -24'sd2000;
                    pr <= 24'sd1234;
                end else begin
                    pl <= 24'sd1000;
                    pr <= -24'sd500;
                end
            end
        end
    end

    initial begin
        pl = 24'sd1000;            // 首窗注入
        pr = -24'sd500;
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        #420000;                   // 覆盖 4+ 个窗口

        if (wins >= 4 && bad == 0)
            $display("TEST PASS : %0d windows verified", wins);
        else
            $display("TEST FAIL : wins=%0d bad=%0d", wins, bad);
        $finish;
    end

    initial #900000 begin $display("TEST TIMEOUT"); $finish; end

endmodule
