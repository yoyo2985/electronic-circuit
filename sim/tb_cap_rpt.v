//------------------------------------------------------------------------------
// tb_cap_rpt.v   voice_cap_rpt 端到端验证: 合成 2 帧特征 → 期望 M-line
//   在 u_cap.send 处逐字节抓 byte_out(114B: 'M'+cnt+13个sum8hex+'\n'),
//   比对期望, 并把行写 cap_rpt_out.log → 外部跑 decode_cap_mem.py 交叉验证。
//   (uart_tx 本身已有其他 tb 验证, 这里验证 cap FSM + hex 格式 + 和累加。)
//   BAUD_TICKS=8(仿真加速), 50MHz(20ns)
//------------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_cap_rpt;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg rst_n;
    reg fe_valid, vad, vad_rise, vad_fall;
    reg [3:0] fe_index;
    reg signed [15:0] fe_data;
    wire tx;

    voice_cap_rpt #(.BAUD_TICKS(8)) u_cap (
        .clk(clk), .rst_n(rst_n),
        .fe_valid(fe_valid), .fe_index(fe_index), .fe_data(fe_data),
        .vad(vad), .vad_rise(vad_rise), .vad_fall(vad_fall),
        .tx(tx)
    );

    // ---- 在 send 处抓字节 ----
    reg [7:0] qbuf[0:1023];
    integer   qlen;

    // ---- 期望值 ----
    integer fd;
    reg [7:0] es[0:113];            // 期望 114 字节
    integer d, n, err;
    reg [31:0] sum_e[0:12];
    reg [7:0] by;

    function [7:0] hexc(input [3:0] n);
        hexc = (n < 4'd10) ? (8'h30 + n) : (8'h37 + n);
    endfunction

    task feed_frame(input integer base);
        integer d;
        begin
            for (d = 0; d < 13; d = d + 1) begin
                fe_valid = 1'b1;
                fe_index = d[3:0];
                fe_data = base + d;     // 帧内 dim_d = base + d
                @(posedge clk);
            end
            fe_valid = 1'b0;
            @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (u_cap.send) begin
            qbuf[qlen] <= u_cap.byte_out;
            qlen <= qlen + 1;
        end
    end

    initial begin
        for (d = 0; d < 13; d = d + 1) sum_e[d] = (d + 1) + (100 + d);   // 帧1 dim=d+1, 帧2 dim=100+d
        // 期望行: 'M' + "00000002" + 13×(sum 8hex ASCII) + '\n'
        es[0] = "M";
        {es[1],es[2],es[3],es[4],es[5],es[6],es[7],es[8]} =
            {8'h30,8'h30,8'h30,8'h30,8'h30,8'h30,8'h30,8'h32};   // cnt=2
        for (d = 0; d < 13; d = d + 1) begin
            for (n = 0; n < 8; n = n + 1)
                es[9 + d*8 + n] = hexc(sum_e[d][(7 - n) * 4 +: 4]);
        end
        es[113] = "\n";

        err = 0;
        rst_n = 1'b0; fe_valid = 0; vad = 0; vad_rise = 0; vad_fall = 0; fe_data = 0;
        qlen = 0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // 段开始
        vad_rise = 1'b1; vad = 1'b1;
        @(posedge clk);
        vad_rise = 1'b0;
        // 送 2 帧(每帧 13 维)
        feed_frame(1);      // base=1: dims 1..13
        feed_frame(100);    // base=100: dims 100..112
        // 段结束
        vad_fall = 1'b1; vad = 1'b0;
        @(posedge clk);
        vad_fall = 1'b0;

        // 等收完 114 字节
        wait (qlen >= 114);
        #100;

        fd = $fopen("cap_rpt_out.log", "w");
        for (n = 0; n < 114; n = n + 1) begin
            by = qbuf[n];
            $fwrite(fd, "%c", by);
            if (by !== es[n]) begin
                if (err < 5)
                    $display("[ERR] byte%0d got=0x%02x want=0x%02x", n, by, es[n]);
                err = err + 1;
            end
        end
        $fclose(fd);
        if (err == 0) $display("CAP PASS : 114-byte M-line exact");
        else          $display("CAP FAIL : err=%0d", err);
        $finish;
    end

    initial #1000000 begin $display("CAP TIMEOUT"); $finish; end

endmodule
