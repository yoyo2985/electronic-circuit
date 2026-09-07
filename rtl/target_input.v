//------------------------------------------------------------------------------
// target_input.v   目标角度输入 + 范围检查（08）
//   由键盘事件逐位组成一个 0..MAX_TARGET(默认180) 的目标角度：
//     key 0..9  = 数字，低位在前依次右移：entry = entry*10 + d
//     key 10    = 清零 CLR（清当前输入并取消已确认目标）
//     key 11    = 确认 ENTER（把当前输入锁存为目标，之后编辑从头开始）
//   范围检查：新组成的数字若 > MAX_TARGET 则拒收该位(entry 不变)并输出 1 拍 over_range。
//   注：key 值由外部键盘映射给定(本项目 keypad_scan 的 key_idx 即丝印键号)。
// 输出：entry 实时编辑值 / target 已确认目标 / over_range 过限脉冲 / target_valid 已确认。
// 参数化：MAX_TARGET。复位：同步、低有效 rst_n。
//------------------------------------------------------------------------------
module target_input #(
    parameter MAX_TARGET = 9'd180
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_event,   // 有效按键事件（1 拍）
    input  wire [3:0]  key,         // 0..9 数字 / 10=CLR / 11=ENTER / 其余忽略
    output reg  [8:0]  entry,       // 当前编辑值(0..MAX_TARGET)
    output reg  [8:0]  target,      // 已确认目标
    output reg         over_range,  // 输入超限脉冲（1 拍）
    output reg         target_valid // 1=已有确认目标
);
    reg [8:0]  acc;
    reg [13:0] tmp;

    always @(posedge clk) begin
        over_range <= 1'b0;
        if (!rst_n) begin
            acc          <= 9'd0;
            entry        <= 9'd0;
            target       <= 9'd0;
            over_range   <= 1'b0;
            target_valid <= 1'b0;
        end else if (key_event) begin
            if (key <= 4'd9) begin                 // 数字位
                tmp = acc * 9'd10 + key;
                if (tmp <= MAX_TARGET) begin
                    acc          <= tmp[8:0];
                    entry        <= tmp[8:0];
                    target_valid <= 1'b0;          // 新编辑使旧目标失效
                end else
                    over_range <= 1'b1;            // 超限：拒收这一位
            end else if (key == 4'd10) begin       // CLR 清零
                acc          <= 9'd0;
                entry        <= 9'd0;
                target_valid <= 1'b0;
            end else if (key == 4'd11) begin       // ENTER 确认
                target       <= acc;
                target_valid <= 1'b1;
                acc          <= 9'd0;              // 下一轮编辑从 0 开始
                entry        <= acc;               // 显示停在刚确认的目标
            end
            // key 12..15 忽略
        end
    end
endmodule
