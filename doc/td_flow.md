# 下板流程：TangDynasty (TD) + EG4S20BG256

> 目标：把 `top_blink` 综合 → 布线 → 位流 → 下载，看到 LED0 心跳、LED7..1 跑灯。
> 约束文件已写好：`constr/top_blink.adc`。`.adc` 是安路 TD 的约束扩展名，
> 语法与引脚从板卡官方 `run_led` 例程抄得，非猜测。

## A. 建工程

1. TD → **New Project**（新建工程）。
2. 器件：**Family = EG4**，**Device = EG4S20BG256**。
3. 工程名 `top_blink_prj`，路径自选。
4. **Add Source**（设计文件）：加入
   - `rtl/top_blink.v`
   - `rtl/clock_enable.v`
   - `rtl/led_ctrl.v`
5. 顶层模块设为 **`top_blink`**。
6. **Add Constraint**（约束文件）：加入 `constr/top_blink.adc`。

## B. 约束文件（已生成，直接加进工程即可）

`constr/top_blink.adc` 内容如下（信号名与 `top_blink` 端口一致）：

```tcl
set_pin_assignment	{ clk }	    { LOCATION = R7;  IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ rst_n }   { LOCATION = A9;  IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[0] }  { LOCATION = B14; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[1] }  { LOCATION = B15; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[2] }  { LOCATION = B16; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[3] }  { LOCATION = C15; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[4] }  { LOCATION = C16; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[5] }  { LOCATION = E13; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[6] }  { LOCATION = E16; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ led[7] }  { LOCATION = F16; IOSTANDARD = LVCMOS33; }
```

- `rst_n = A9` 就是 SW0：拨上=运行，拨下=复位（低有效）。
- 若要自己改：语法固定为 `set_pin_assignment {端口名} { LOCATION = 引脚; IOSTANDARD = LVCMOS33; }`，总线（如 `led[7:0]`）逐位写 `led[0]`…`led[7]`。

## C. 综合与位流

1. Flow 里依次（或 Run All 一键）：
   - **Compile / Synthesize**（综合）
   - **Map**（映射）
   - **Place & Route**（布局布线）
   - **Generate Bitstream**（生成 .bit）
2. 看报告：资源占用（LUT 应远小于 19600）、时序、引脚是否与上表一致。

## D. 下载

1. USB 线接板卡 **USB-JTAG** 口，上电。
2. TD → **Tools → Programmer**（编程器）。
3. 选电缆 **Anlogic USB-JTAG**，加载生成的 `.bit`，**Program** 下载。

## E. 现场预期

- SW0 拨**上**（运行）：LED0 1Hz 心跳，LED1→2→…→7→1 跑灯循环。
- SW0 拨**下**（复位）：全部按复位态。
- 不亮/乱闪：先查 .adc 引脚是否加对、SW0 是否被拨下、.bit 是否下载成功。

## F. 官方例程参考（重要，后续阶段直接用）

板卡官方数字电路例程已解压到：
`E:/electronic-circuit/_extract_basic/Codes_Basic/Codes/`

| 目录 | 内容 | 后续对应 |
|---|---|---|
| `1 run_led` | 跑灯 | 本阶段参考 |
| `6 counter24` / `8 clock` / `10 binary2bcd` | 数码管 | 下一轮数码管 |
| `9 keyboard` | 矩阵键盘 | 按键阶段 |
| `11 pwm` / `12.2 R2R_DAC_DDS` | PWM / DAC | 加分项 |
| `13 AD` / `14.1 uart_rx_top` / `14.2 uart_tx_top` | ADC / 串口 | UART 阶段 |

每个子目录都带 `.adc`（引脚）+ `.v`（写法）。后续做数码管/按键/UART 时，我会从这些官方例程里取引脚，而不是凭记忆。
