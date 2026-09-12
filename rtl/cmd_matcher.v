//------------------------------------------------------------------------------
// cmd_matcher.v   KWS 多模板 L1 匹配（并行 4 个 vtmpl + 最小距离比较树）
//   输入：mfcc_valid/mfcc_data(13 维逐维串行) → 内部 4 个 vtmpl(DIM13) 并行
//   每帧(13 维收齐)后：cmd_valid/cmd_id=最小距离模板索引/cmd_dist_min。
//   cmd_id 编码(与 decision_fsm 一致): 0=停 1=左 2=右 3=前。
//   模板: 参数内嵌常量(与 speaker_verify.v 同口径, 源自 data/commands/cmd_{stop,left,right,forward}.mem;
//         字面量 {dim12..dim0} 高位在前 —— TD 不支持 $readmemh 载入 ROM)。
//------------------------------------------------------------------------------
module cmd_matcher #(
    parameter DIM    = 13,
    parameter NUM    = 4,
    parameter TH     = 2000000,
    parameter [207:0] TPL0 = 208'h00520020008300ae009fffd8fefeff93fe4efe870375f9b40868, // stop (cap3 4段)
    parameter [207:0] TPL1 = 208'h004e008700a3006300840078ffcfffddfd71fc6201fffb410a8b, // left
    parameter [207:0] TPL2 = 208'h004300b900dd00800099009cffd0ff74fcf8fbea018dfbe60b78, // right
    parameter [207:0] TPL3 = 208'h002cfff40094010300d8fffeff17ff31fdacfe430397fa0e08c1  // forward (cap3 5段)
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              mfcc_valid,       // feature_engine.feature_valid
    input  wire signed [15:0] mfcc_data,       // feature_engine.feature_data
    output reg               cmd_valid,        // 每帧判定
    output reg  [1:0]        cmd_id,           // 0..3
    output reg  [31:0]       cmd_dist_min
);
    wire v0, v1, v2, v3;
    wire [31:0] d0, d1, d2, d3;
    wire m0, m1, m2, m3;

    vtmpl #(.DIM(DIM), .TH(TH), .TPLV(TPL0)) u0 (
        .clk(clk), .rst_n(rst_n), .in_valid(mfcc_valid), .in_v(mfcc_data),
        .out_valid(v0), .out_dist(d0), .out_match(m0));
    vtmpl #(.DIM(DIM), .TH(TH), .TPLV(TPL1)) u1 (
        .clk(clk), .rst_n(rst_n), .in_valid(mfcc_valid), .in_v(mfcc_data),
        .out_valid(v1), .out_dist(d1), .out_match(m1));
    vtmpl #(.DIM(DIM), .TH(TH), .TPLV(TPL2)) u2 (
        .clk(clk), .rst_n(rst_n), .in_valid(mfcc_valid), .in_v(mfcc_data),
        .out_valid(v2), .out_dist(d2), .out_match(m2));
    vtmpl #(.DIM(DIM), .TH(TH), .TPLV(TPL3)) u3 (
        .clk(clk), .rst_n(rst_n), .in_valid(mfcc_valid), .in_v(mfcc_data),
        .out_valid(v3), .out_dist(d3), .out_match(m3));

    reg pending;
    reg [31:0] sel_min;
    reg [1:0]  sel_id;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            pending <= 1'b0; cmd_valid <= 1'b0; cmd_id <= 0; cmd_dist_min <= 0;
            sel_min <= 0; sel_id <= 0;
        end else begin
            cmd_valid <= 1'b0;
            if (v0) pending <= 1'b1;                 // 帧结束（4 个同步）
            else if (pending) begin
                // 比较树：d0 基准
                sel_min = d0; sel_id = 2'd0;
                if (d1 < sel_min) begin sel_min = d1; sel_id = 2'd1; end
                if (d2 < sel_min) begin sel_min = d2; sel_id = 2'd2; end
                if (d3 < sel_min) begin sel_min = d3; sel_id = 2'd3; end
                cmd_id      <= sel_id;
                cmd_dist_min<= sel_min;
                cmd_valid   <= 1'b1;
                pending     <= 1'b0;
            end
        end
    end

endmodule
