//------------------------------------------------------------------------------
// ctl_chain.v   决策→运动 串链（decision_fsm → motion_plan）
//   语音(VAD)+声纹(owner)+方向 → 左/右轮速，供 V1 虚拟机器人。
//------------------------------------------------------------------------------
module ctl_chain #(
    parameter VF = 80,
    parameter VT = 50
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              in_valid,
    input  wire              in_vad,
    input  wire              in_auth,
    input  wire [1:0]        in_dir,
    output wire              out_valid,
    output wire signed [7:0] vl,
    output wire signed [7:0] vr
);
    wire act_ok;
    wire [2:0] act;

    decision_fsm u_dec (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_vad(in_vad), .in_auth(in_auth), .in_dir(in_dir),
        .action_valid(act_ok), .action(act)
    );

    motion_plan #(.VF(VF), .VT(VT)) u_mot (
        .clk(clk), .rst_n(rst_n), .in_valid(act_ok), .action(act),
        .out_valid(out_valid), .vl(vl), .vr(vr)
    );
endmodule
