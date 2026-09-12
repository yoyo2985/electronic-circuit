//------------------------------------------------------------------------------
// tb_dir_energy.v  双麦方向判决验证: 合成已知 L/R 幅度比的语音段
//   期望: L/R=2.5→左, R/L=2.5→右, 1.11→中, 恰好1.25→中(不严格大于), 1.266→左
//------------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_dir_energy;
    reg clk=0; always #10 clk=~clk;
    reg rst_n, sample_ok, vad, vad_rise, vad_fall;
    reg signed [23:0] pl, pr;
    wire [1:0] dir; wire dir_valid;
    dir_energy u_dut(.clk(clk),.rst_n(rst_n),.sample_ok(sample_ok),
        .pcm_l(pl),.pcm_r(pr),.vad(vad),.vad_rise(vad_rise),.vad_fall(vad_fall),
        .dir(dir),.dir_valid(dir_valid));
    integer fails=0, pass=0, i, A, B;
    task seg(input integer al, input integer ar, input [1:0] exp, input [255:0] nm);
        begin
            A=al; B=ar;
            vad_rise=1; vad=1; @(posedge clk); vad_rise=0;
            for (i=0;i<4000;i=i+1) begin sample_ok=1; pl=A[23:0]; pr=B[23:0]; @(posedge clk); end
            sample_ok=0; vad_fall=1; vad=0; @(posedge clk); vad_fall=0; @(posedge clk);
            if (dir!==exp) begin $display("FAIL %0s L=%0d R=%0d dir=%0d exp=%0d",nm,A,B,dir,exp); fails=fails+1; end
            else begin $display("PASS %0s dir=%0d",nm,dir); pass=pass+1; end
            repeat(3) @(posedge clk);
        end
    endtask
    initial begin
        rst_n=0; sample_ok=0; vad=0; vad_rise=0; vad_fall=0; pl=0; pr=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
        seg(1000, 400, 2'd1, "left  L/R=2.5");
        seg(400, 1000, 2'd2, "right R/L=2.5");
        seg(1000, 900, 2'd0, "center 1.11");
        seg(1000, 800, 2'd0, "boundary 1.25 -> center");
        seg(1000, 790, 2'd1, "just-off 1.266 -> left");
        seg(500, 500, 2'd0, "equal -> center");
        seg(0, 0, 2'd0, "silence -> center");
        if (fails==0) $display("DIR PASS : %0d/%0d",pass,pass);
        else $display("DIR FAIL : %0d",fails);
        $finish;
    end
    initial #2000000 begin $display("TIMEOUT"); $finish; end
endmodule
