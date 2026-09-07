# 第一轮模块接口与预期波形

## 1. clock_enable

接口：

```verilog
module clock_enable #(parameter MS_DIV = 50000) (
    input  wire clk,       // 50 MHz
    input  wire rst_n,     // 同步复位，低有效
    output reg  tick_1ms   // 每 MS_DIV 拍 1 个 1 拍宽脉冲
);
```

- `clk`：唯一主时钟。`rst_n`：同步复位。
- `tick_1ms`：高电平只持续 1 个时钟周期，每 `MS_DIV` 个时钟出现一次。
- 仿真把 `MS_DIV` 改小（如 50）即可快速看到脉冲。

**预期波形**：`tick_1ms` 每隔 `MS_DIV` 个 `clk` 出现一次单周期尖峰；`rst_n=0` 期间恒 0。
**不对时检查**：`MS_DIV` 是否被参数覆盖、复位是否同步、`cnt` 是否在 `MS_DIV-1` 回零。

## 2. led_ctrl

接口：

```verilog
module led_ctrl #(parameter BLANK_HALF_MS=500, WALK_STEP_MS=250) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1ms,   // 来自 clock_enable
    output reg  [7:0] led        // {LED7..LED0}，高=点亮
);
```

- `led[0]` = 心跳，每 `BLANK_HALF_MS*2` ms 翻转（默认 1 Hz）。
- `led[7:1]` = 跑灯，7 位中 1 位为 1，每 `WALK_STEP_MS` ms 左移一位。

**预期波形**：`LED0` 周期翻转；`LED7..1` 单 bit 逐位左移并循环。
**不对时检查**：`tick_1ms` 是否真的在动、计数比较是否用 `== MS-1`、`walk` 旋转方向 `{walk[5:0],walk[6]}`。

## 3. seven_seg

接口：

```verilog
module seven_seg (
    input  wire        clk, rst_n, tick_scan,
    input  wire [15:0] bcd_data,  // [3:0]=个位(最右) … [15:12]=千位(最左)
    input  wire [3:0]  points,     // 小数点，bit 对应各位
    input  wire [3:0]  blank,      // 消隐，bit 对应各位
    output reg  [7:0]  seg,        // {DOT,G,F,E,D,C,B,A} → Digitron_Out[7:0]
    output reg  [3:0]  dig_cs      // 低有效, [0]=COM4 最右
);
```

字形表（共阴，高=亮）：

| 数字 | seg (DOTGFEDCBA) | 十六进制 |
|---|---|---|
| 0 | 00111111 | 0x3F |
| 1 | 00000110 | 0x06 |
| 2 | 01011011 | 0x5B |
| 3 | 01001111 | 0x4F |
| 4 | 01100110 | 0x66 |
| 5 | 01101101 | 0x6D |
| 6 | 01111101 | 0x7D |
| 7 | 00000111 | 0x07 |
| 8 | 01111111 | 0x7F |
| 9 | 01101111 | 0x6F |

tb 用 `bcd_data=16'h0090, blank=4'b1000` 显示 " 090"，预期每位：

| dig_idx | dig_cs | seg(二进制) | 字形 |
|---|---|---|---|
| 0 (最右) | 1110 | 00111111 | 0 |
| 1 | 1101 | 01101111 | 9 |
| 2 | 1011 | 00111111 | 0 |
| 3 (最左) | 0111 | 00000000 | 消隐 |

**不对时检查**：字形表位序、片选极性（低有效）、BCD 位序、`blank` 对应位。
