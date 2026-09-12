`timescale 1ns/1ps
module tb_seg_decide;
  reg clk=0; always #10 clk=~clk;
  reg rst_n, fe_valid; reg [3:0] fe_index; reg signed [15:0] fe_data;
  reg vad, vad_rise, vad_fall;
  wire owner_valid, seg_done; wire [1:0] cmd_id; wire [15:0] own_mean;
  seg_decide u_seg(.clk(clk),.rst_n(rst_n),.fe_valid(fe_valid),.fe_index(fe_index),
    .fe_data(fe_data),.vad(vad),.vad_rise(vad_rise),.vad_fall(vad_fall),
    .owner_valid(owner_valid),.seg_done(seg_done),.cmd_id(cmd_id),.own_mean(own_mean));
  integer fails=0, pass=0; reg [1:0] exp_cmd; reg exp_own; reg seen;
  reg signed [15:0] V [0:12];
  always @(posedge clk) if (seg_done) seen<=1;
  task chk(input [255:0] nm, input [1:0] ec, input eo); begin
    if (!seen) begin $display("FAIL %0s: no seg_done pulse",nm); fails=fails+1; end
    else if (cmd_id!==ec||owner_valid!==eo) begin
      $display("FAIL %0s: cmd=%0d(exp %0d) own=%0b(exp %0b) mean=%0d",nm,cmd_id,ec,owner_valid,eo,own_mean); fails=fails+1; end
    else begin $display("PASS %0s: cmd=%0d own=%0b mean=%0d",nm,cmd_id,owner_valid,own_mean); pass=pass+1; end end endtask
  task feed(input integer n); integer f,i; begin
    seen=0;
    vad_rise=1; vad=1; @(posedge clk); vad_rise=0;
    for (f=0;f<n;f=f+1) for (i=0;i<13;i=i+1) begin fe_valid=1; fe_index=i[3:0]; fe_data=V[i]; @(posedge clk); end
    fe_valid=0; vad_fall=1; vad=0; @(posedge clk); vad_fall=0;
    repeat(60) @(posedge clk); end endtask
  initial begin
    rst_n=0; fe_valid=0; fe_index=0; fe_data=0; vad=0; vad_rise=0; vad_fall=0; seen=0;
    repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
    // forward_tpl exp cmd=3 own=1
    V[0]=16'sh08c1;
    V[1]=16'shfa0e;
    V[2]=16'sh0397;
    V[3]=16'shfe43;
    V[4]=16'shfdac;
    V[5]=16'shff31;
    V[6]=16'shff17;
    V[7]=16'shfffe;
    V[8]=16'sh00d8;
    V[9]=16'sh0103;
    V[10]=16'sh0094;
    V[11]=16'shfff4;
    V[12]=16'sh002c;
    feed(100);
    chk("forward_tpl",2'd3,1'b1);
    // stop_tpl exp cmd=0 own=1
    V[0]=16'sh0868;
    V[1]=16'shf9b4;
    V[2]=16'sh0375;
    V[3]=16'shfe87;
    V[4]=16'shfe4e;
    V[5]=16'shff93;
    V[6]=16'shfefe;
    V[7]=16'shffd8;
    V[8]=16'sh009f;
    V[9]=16'sh00ae;
    V[10]=16'sh0083;
    V[11]=16'sh0020;
    V[12]=16'sh0052;
    feed(100);
    chk("stop_tpl",2'd0,1'b1);
    // owner_tpl exp cmd=2 own=1
    V[0]=16'sh0bc9;
    V[1]=16'shfb50;
    V[2]=16'sh0179;
    V[3]=16'shfc85;
    V[4]=16'shfd0a;
    V[5]=16'shff66;
    V[6]=16'shffbc;
    V[7]=16'sh004a;
    V[8]=16'sh008c;
    V[9]=16'sh00f2;
    V[10]=16'sh00f9;
    V[11]=16'sh0051;
    V[12]=16'sh001c;
    feed(100);
    chk("owner_tpl",2'd2,1'b1);
    // far_all20k exp cmd=2 own=0
    V[0]=16'sh4e20;
    V[1]=16'sh4e20;
    V[2]=16'sh4e20;
    V[3]=16'sh4e20;
    V[4]=16'sh4e20;
    V[5]=16'sh4e20;
    V[6]=16'sh4e20;
    V[7]=16'sh4e20;
    V[8]=16'sh4e20;
    V[9]=16'sh4e20;
    V[10]=16'sh4e20;
    V[11]=16'sh4e20;
    V[12]=16'sh4e20;
    feed(100);
    chk("far_all20k",2'd2,1'b0);
    // owner_fwd_like exp cmd=3 own=1
    V[0]=16'sh08c1;
    V[1]=16'shf9f0;
    V[2]=16'sh03ab;
    V[3]=16'shfe39;
    V[4]=16'shfdac;
    V[5]=16'shff31;
    V[6]=16'shff17;
    V[7]=16'shfffe;
    V[8]=16'sh00d8;
    V[9]=16'sh0103;
    V[10]=16'sh0094;
    V[11]=16'shfff4;
    V[12]=16'sh002c;
    feed(100);
    chk("owner_fwd_like",2'd3,1'b1);
    // stranger_like exp cmd=2 own=0
    V[0]=16'sh1781;
    V[1]=16'shfed4;
    V[2]=16'sh02a5;
    V[3]=16'shfdb1;
    V[4]=16'shfc42;
    V[5]=16'shfffc;
    V[6]=16'shff26;
    V[7]=16'shffe6;
    V[8]=16'shfff6;
    V[9]=16'sh0156;
    V[10]=16'sh0081;
    V[11]=16'sh00ab;
    V[12]=16'sh006c;
    feed(100);
    chk("stranger_like",2'd2,1'b0);
    if(fails==0) $display("SEG_DECIDE PASS : %0d/%0d",pass,pass);
    else $display("SEG_DECIDE FAIL : %0d fails",fails);
    $finish; end
  initial #3000000 begin $display("TIMEOUT"); $finish; end
endmodule
