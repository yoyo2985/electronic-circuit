//------------------------------------------------------------------------------
// direction3.v   D1 三态声源方向（L/R 能量差 + 滞回）
//   每窗(energy 窗口)喂入 el/er(平均|幅度| 同尺度)，输出 0=中/1=左/2=右。
//   滞回：中区±TH_ON 进入左/右；回到中心需差过 TH_OFF(<TH_ON)防抖。
// 与 py/gen_direction3.py 同一规则。复位：同步低有效。
//------------------------------------------------------------------------------
module direction3 #(
    parameter EW = 24,
    parameter TH_ON  = 200,
    parameter TH_OFF = 60
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              in_valid,      // 每窗 1 拍
    input  wire [EW-1:0]     e_l,
    input  wire [EW-1:0]     e_r,
    output reg               out_valid,
    output reg  [1:0]        dir            // 0=中, 1=左, 2=右
);
    localparam [1:0] C = 2'd0, L = 2'd1, R = 2'd2;
    reg [1:0] st;
    reg [1:0] nxt;
    reg signed [EW:0] diff;

    always @(posedge clk) begin : proc
        if (!rst_n) begin
            st        <= C;
            dir       <= C;
            out_valid <= 1'b0;
            diff      <= {EW+1{1'b0}};
            nxt       <= C;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                diff = $signed({1'b0, e_l}) - $signed({1'b0, e_r});
                case (st)
                    C: begin
                        if (diff >= TH_ON)       nxt = L;
                        else if (diff <= -TH_ON) nxt = R;
                        else                     nxt = C;
                    end
                    L: nxt = (diff < TH_OFF) ? C : L;
                    default: nxt = (diff > -TH_OFF) ? C : R;
                endcase
                st        <= nxt;
                dir       <= nxt;         // 本窗新状态即输出方向
                out_valid <= 1'b1;
            end
        end
    end
endmodule
