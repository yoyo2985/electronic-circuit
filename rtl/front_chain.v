//------------------------------------------------------------------------------
// front_chain.v   B3 前端链：预加重(pre_emph) → 分帧+加窗(front_wind)
//   输入：连续 24bit PCM（每采样 sample_ok 1 拍 @48k）
//   输出：加窗帧字流，每帧 N 拍；out_first 标帧首。
//   供后续 FFT 使用。pre_emph 有 1 拍流水，用 out_valid 打给 front_wind.sample_ok，
//   采样节拍不变（每采样一对，仅整体延迟 1 拍）。
// 复位：同步低有效 rst_n。
//------------------------------------------------------------------------------
module front_chain #(
    parameter AW    = 24,
    parameter N     = 64,
    parameter Q     = 14,
    parameter A_FIX = 15892
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_ok,
    input  wire signed [AW-1:0] sample,
    output wire              frame_valid,   // 加窗帧输出有效(每帧连续 N 拍)
    output wire              frame_first,   // 帧首字
    output wire signed [AW-1:0] frame_data
);
    wire pe_valid;
    wire signed [AW-1:0] pe_data;

    pre_emph #(.AW(AW), .Q(Q), .A_FIX(A_FIX)) u_pe (
        .clk(clk), .rst_n(rst_n),
        .in_valid(sample_ok), .x(sample),
        .out_valid(pe_valid), .y(pe_data)
    );

    front_wind #(.AW(AW), .N(N)) u_wind (
        .clk(clk), .rst_n(rst_n),
        .sample_ok(pe_valid), .sample(pe_data),
        .out_valid(frame_valid), .out_first(frame_first), .out_data(frame_data)
    );
endmodule
