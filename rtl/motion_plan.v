//------------------------------------------------------------------------------
// motion_plan.v   E1 决策动作 → 差分轮速(VL,VR)
//   0/1(IDLE/REJECT)→(0,0); 2 FORWARD→(VF,VF); 3 LEFT→(-VT,VT); 4 RIGHT→(VT,-VT)
//   给 V1 虚拟机器人(virtual_motor)作为目标左/右轮速度。
//------------------------------------------------------------------------------
module motion_plan #(
    parameter VF = 80,
    parameter VT = 50
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire [2:0]       action,
    output reg              out_valid,
    output reg  signed [7:0] vl,
    output reg  signed [7:0] vr
);
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            vl <= 8'sd0; vr <= 8'sd0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                case (action)
                    3'd2: begin vl <= VF[7:0]; vr <= VF[7:0]; end
                    3'd3: begin vl <= -VT[7:0]; vr <= VT[7:0]; end
                    3'd4: begin vl <= VT[7:0]; vr <= -VT[7:0]; end
                    default: begin vl <= 8'sd0; vr <= 8'sd0; end
                endcase
                out_valid <= 1'b1;
            end
        end
    end
endmodule
