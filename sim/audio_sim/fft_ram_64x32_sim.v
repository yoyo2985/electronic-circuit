// fft_ram_64x32_sim.v — 本地 ModelSim 行为级替身(与 IP 同名, 仅仿真用, 不进 TD 综合)
//   语义: 单口 64x32, NORMAL 写; 读 = 2 拍(块内 reg + OUTREG), 与 IP REGMODE_A="OUTREG" 对应。
//   工程里仿真请编译本文件而不是 rtl/ip/fft_ram_64x32.v(TD 真机用那个 + 其原语)。
module fft_ram_64x32 (doa, dia, addra, cea, ocea, clka, wea, rsta);
  output [31:0] doa;
  input  [31:0] dia;
  input  [5:0]  addra;
  input  wea, cea, ocea, clka, rsta;
  reg [31:0] mem [0:63];
  reg [31:0] core_q;   // 块内读寄存器
  reg [31:0] out_q;    // OUTREG 输出寄存器
  always @(posedge clka) begin
    if (cea) begin
      if (wea) mem[addra] <= dia;
      core_q <= mem[addra];          // 读(与写并行时为 NORMAL: 读旧值或未定义, 由使用者错开)
    end
  end
  always @(posedge clka) begin
    if (ocea) out_q <= core_q;       // OUTREG
  end
  assign doa = out_q;
endmodule
