// 行为级 stub（仅仿真/例化检查用，下板用 rtl/audio/clk_wiz_0.v 真 PLL）
module clk_wiz_0 (
  input  refclk, reset, stdby,
  output reg extlock,
  output clk0_out, clk1_out
);
  reg [7:0] c = 0;
  always @(posedge refclk) begin
    if (reset) begin c <= 0; extlock <= 1'b0; end
    else if (c < 8'd100) begin c <= c + 1'b1; end
    else extlock <= 1'b1;
  end
  assign clk0_out = refclk;
  assign clk1_out = refclk;   // 仅接线检查
endmodule
