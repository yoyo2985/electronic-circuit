//------------------------------------------------------------------------------
// speaker_verify.v   B5.3 feature_engine → vtmpl 声纹认证适配器
//   feature_engine 每帧连续送 13 个 MFCC(feature_index 0..12) → 本模块按帧直通喂
//   vtmpl#(DIM=13)；vtmpl 在第 13 维给该帧 dist/match → 输出 owner_valid(单帧)。
//   模板来自 data/spk_tpl.mem；TH 顶层参数(由 Python 数据定，勿拍脑袋)。
//------------------------------------------------------------------------------
module speaker_verify #(
    parameter DIM = 13,
    parameter TH  = 5000,
    parameter TPL = "data/spk_tpl.mem"
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                fe_feature_valid,
    input  wire [3:0]          fe_index,          // 0..DIM-1
    input  wire signed [15:0]  fe_feature_data,
    output reg                 frame_valid,       // 一帧完成(该帧判定有效)
    output reg  [31:0]         frame_dist,
    output reg                 frame_match,
    output reg                 owner_valid        // 单帧判定(可再被片段投票)
);
    wire v_ok;
    wire [31:0] v_dist;
    wire v_match;

    vtmpl #(.DIM(DIM), .TH(TH), .TPL(TPL)) u_vt (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fe_feature_valid), .in_v(fe_feature_data),
        .out_valid(v_ok), .out_dist(v_dist), .out_match(v_match)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_valid <= 1'b0;
            frame_dist  <= 32'd0;
            frame_match <= 1'b0;
            owner_valid <= 1'b0;
        end else begin
            frame_valid <= v_ok;                 // vtmpl 每组(帧)完成
            if (v_ok) begin
                frame_dist  <= v_dist;
                frame_match <= v_match;
                owner_valid <= v_match;
            end
        end
    end
endmodule
