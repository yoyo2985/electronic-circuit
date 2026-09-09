//------------------------------------------------------------------------------
// top_target.v   08 目标角度输入演示（顶层，含蜂鸣器反馈）
//   用 4x4 键盘输入 0..180 的目标角度：
//     KEY0..9 = 数字，逐位输入(实时显示在数码管) → 蜂鸣器短"嘀"一声
//     KEY10   = 清零 CLR；KEY11 = 确认 ENTER → 各自不同的提示音
//   超限(>180)该位拒收，LED1 亮一下提示；确认后 LED0 常亮表示已锁定目标。
//   数码管显示：编辑中显示当前输入，确认后显示目标值(0..180，右对齐去前导0)。
//   蜂鸣器(Buzzer_Out=H11, 无源)：数字键=2kHz/80ms，CLR=800Hz/150ms，ENTER=3kHz/120ms。
//   注：keypad_scan 的 key_idx 即丝印 KEY 编号(05 实测)。
// 参数化：MS_DIV / DEBOUNCE_N / 各音效 FREQ/DUR。复位：SW0(A9)=rst_n。
//------------------------------------------------------------------------------
module top_target #(
    parameter MS_DIV     = 50000,
    parameter DEBOUNCE_N = 3,
    parameter BEEP_DIG_FREQ  = 2000,
    parameter BEEP_DIG_DUR   = 80,
    parameter BEEP_CLR_FREQ  = 800,
    parameter BEEP_CLR_DUR   = 150,
    parameter BEEP_ENT_FREQ  = 3000,
    parameter BEEP_ENT_DUR   = 120
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] col,
    output wire [3:0] row,
    output wire [7:0] seg,
    output wire [3:0] dig_cs,
    output wire [7:0] led,
    output wire       buzzer_out
);
    wire tick_1ms;
    clock_enable #(.MS_DIV(MS_DIV)) u_clk_en (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms)
    );

    wire key_event;
    wire [3:0] key_idx;
    keypad_scan #(.DEBOUNCE_N(DEBOUNCE_N)) u_keypad (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .col_in(col), .row_out(row),
        .key_event(key_event), .key_idx(key_idx)
    );

    wire [8:0] entry, target;
    wire over_range, target_valid;
    target_input u_ti (
        .clk(clk), .rst_n(rst_n), .key_event(key_event), .key(key_idx),
        .entry(entry), .target(target),
        .over_range(over_range), .target_valid(target_valid)
    );

    // 显示值：已确认显示目标，否则显示当前输入
    wire [8:0] dv = target_valid ? target : entry;
    reg [3:0] hun, ten, uni;
    always @(*) begin
        hun = dv / 100;
        ten = (dv / 10) % 10;
        uni = dv % 10;
    end
    wire [3:0] blank = {1'b1, (dv < 9'd100), (dv < 9'd10), 1'b0};   // 右对齐去前导0

    seven_seg u_seg (
        .clk(clk), .rst_n(rst_n), .tick_scan(tick_1ms),
        .bcd_data({4'd0, hun, ten, uni}), .points(4'b0000), .blank(blank),
        .seg(seg), .dig_cs(dig_cs)
    );

    // LED0=已确认目标；LED1=超限提示(持续到下一个按键)
    reg over_latch;
    always @(posedge clk) begin
        if (!rst_n)      over_latch <= 1'b0;
        else if (key_event) over_latch <= 1'b0;
        else if (over_range) over_latch <= 1'b1;
    end
    assign led = {6'b000000, over_latch, target_valid};

    // ---- 蜂鸣器反馈：数字/清除/确认 三种音效 ----
    wire key_digit = key_event && (key_idx <= 4'd9);
    wire key_clr   = key_event && (key_idx == 4'd10);
    wire key_enter = key_event && (key_idx == 4'd11);

    wire bz_digit, bz_clr, bz_enter;
    beep_gen #(.FREQ_HZ(BEEP_DIG_FREQ), .DUR_MS(BEEP_DIG_DUR)) u_bz_digit (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_digit), .buzzer(bz_digit)
    );
    beep_gen #(.FREQ_HZ(BEEP_CLR_FREQ), .DUR_MS(BEEP_CLR_DUR)) u_bz_clr (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_clr), .buzzer(bz_clr)
    );
    beep_gen #(.FREQ_HZ(BEEP_ENT_FREQ), .DUR_MS(BEEP_ENT_DUR)) u_bz_enter (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .trigger(key_enter), .buzzer(bz_enter)
    );
    // 无源蜂鸣器由方波驱动；同一时刻最多一个音效在响，直接按位或
    assign buzzer_out = bz_digit | bz_clr | bz_enter;
endmodule
