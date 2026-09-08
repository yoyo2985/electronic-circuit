# A1 音频采集最小系统 —— 上板指南（EG4S20 + ES8388 双麦）

> 里程碑目标：证明 **ES8388 → I2S → FPGA** 拿到 **48kHz 左右两路独立 PCM**。
> 这是声纹认证/声源定位/TDOA 的底层根基。本工程独立，**不影响**已跑通的 V1 闭环工程。

## 验收标准（上板后）
1. 对 **mic1（左咪头）** 说话、捂住 mic2 → `led[7:4]`（左）亮，`led[3:0]`（右）不动。
2. 对 **mic2** 说话 → 反过来。→ 两路独立即证明，可进 TDOA。
3. 串口每 0.5s 收一行 `Pxxxx Lxxxx Rxxxx Vx`（P=帧数 ≈5DC0=codec 正常；L/R=左右能量峰值；V=0/1 语音活动，有语音变 1）。

## 已交付文件
| 文件 | 说明 |
|---|---|
| `rtl/top_audio.v` | 顶层：PLL→MCLK + ES8388 配置 + 采集 + 能量 + LED/UART |
| `rtl/audio_pcm_bridge.v` | I2S 收左右 24bit + 跨时钟成帧（**新写**） |
| `rtl/audio_energy.v` | 每声道 1024 帧窗口平均 \|x\|（**新写**） |
| `rtl/audio_rpt.v` | 按窗细报 UART ASCII（备用） |
| `rtl/audio_status.v` | 调试状态行：每 0.5s 发 `Pxxxx Lxxxx Rxxxx Vx`（**当前顶层用这个**，V=VAD） |
| `rtl/audio/` | 复用官方配置链 `es8388_config / i2c_reg_cfg / i2c_dri` + 真 PLL `clk_wiz_0.v` |
| `constr/top_audio.adc` | 引脚约束（aud_* 照官方例程，与 V1 工程零冲突） |
| `sim/tb_audio_pcm_bridge.v` `tb_audio_energy.v` `tb_audio_rpt.v` | 三个已跑 PASS 的 Testbench |
| `tools/audio_monitor.py` | 串口监视（只显示，不参与链路） |

## 0. 接线：你的模块是 10 脚散线版（ES8388 + PAM8406）
| 模块脚 | 接到 FPGA/电源 | FPGA 脚 |
|---|---|---|
| MCK | `aud_mclk` | N5 |
| BCK | `aud_bclk` | M6 |
| WS | `aud_lrc` | M7 |
| DO | `aud_adcdat` | R14 |
| DI | `aud_dacdat` | P6 |
| SCL | `aud_scl` | R12 |
| SDA | `aud_sda` | R9 |
| PEN | **GND**（功放开，低=关；A1 只采集不需要） | — |
| VCC | 板子扩展排针 **5V** 脚（先量后接，别接 3V3） | — |
| GND | 板子 **GND**（共地） | — |

- 先量再插：USB 供电→万用表 DC 档→黑笔 GND、红笔找 ≈5V 脚→**断电**后接好→上电。
- 方向：沿用官方固件 ES8388 主时钟模式，**BCK/WS/DO 是模块输出**给 FPGA。
- 电平：ES8388 数字口都是 3.3V 域，与 FPGA 3.3V 直连安全；VCC 只给模块，别把 5V 接到 FPGA 3.3 引脚。

## 0.5 接线自检固件（怀疑接线/供电时先用它）
文件：`rtl/top_audio_wiretest.v`（顶层）+ `rtl/sig_activity.v` + `constr/top_audio_wiretest.adc`。
它只做：出 MCLK → I2C 配置 ES8388 → 用 LED 显示模块回送的三根线是否有活动：
- `led0`=BCK(M6) 有翻转；`led1`=WS(M7) 有翻转；`led2`=DO(R14) 有翻转（说话才亮）。
判读：全灭=供电/MCK/配置(地址)问题；led0 亮=codec 已起来；led0亮 led1灭=WS 线错；led1亮 led2 说话不亮=DO 线/咪头。
TD 工程文件：top_audio_wiretest.v、sig_activity.v、clock_enable.v、audio/i2c_dri.v、audio/i2c_reg_cfg.v、audio/es8388_config.v、audio/clk_wiz_0.v；顶层选 top_audio_wiretest；约束 top_audio_wiretest.adc。

## 1. 仿真（可选，确认即可）
ModelSim 打开，进 `sim/audio_sim/`，执行：
```
do run_audio.do
```
依次跑 bridge/energy/rpt，三个都应打印 `TEST PASS`。

## 2. TD 建工程（步骤）
1. 新建工程 `top_audio`，器件 EG4S20BG256。
2. 添加源码（顶层选 **top_audio**）：
   - `rtl/top_audio.v`
   - `rtl/clock_enable.v`、`rtl/uart_tx.v`（V1 复用件）
   - `rtl/audio_pcm_bridge.v`、`rtl/audio_energy.v`、`rtl/audio_status.v`（`audio_rpt.v` 可选不用）
   - `rtl/audio/es8388_config.v`、`rtl/audio/i2c_reg_cfg.v`、`rtl/audio/i2c_dri.v`
   - `rtl/audio/clk_wiz_0.v`（**真 PLL**，不要用 sim 下的 `_sim_clk_wiz_0.v` stub）
3. 约束：`constr/top_audio.adc`（加进工程即可自动生效）。
4. 综合 → 布局布线 → 生成比特流 → 下载。

## 3. 上板
- 音频模块插好，**两只咪头已接 mic1 / mic2**。
- `SW0` 拨上（A9，=高）= 运行。
- 上电后约 0.2s（等 ES8388 配置完）LED 开始反映能量：
  - `led[7:4]` = 左声道电平（4 级对数条），`led[3:0]` = 右声道。
- 串口 115200 接 `tx`(D12)：用之前 V1 的 CH340 那一套或板载 UART 口。
  ```
  python tools/audio_monitor.py COMx
  ```

## 4. 故障排查
| 现象 | 处理 |
|---|---|
| 左右反了 | **不动代码**，顶层 `top_audio.v` 交换 `u_br` 的 `pcm_l/pcm_r` |
| 两只咪头说话灯都一样 | 说明 mic1/mic2 被接成同一声道 → 检查咪头接线/模块丝印 |
| LED 完全不动 | ①咪头增益：把 `u_cfg.volume` 或 `i2c_reg_cfg` 里 R0x10/0x11(PGA) 调大；②先看 V1 的官方回环例程是否出声，排除模块/接线 |
| 串口没数据 | 先看 LED 是否在动（链路好但串口问题）；查 COM 口/115200/接线 D12 |

## 5. 本阶段的取舍（记录，不改）
- 沿用官方 **codec 主时钟** 模式（BCLK/LRCK 由 ES8388 自己产生，FPGA 只供 MCLK）。跨时钟用"L/R 成帧 + 握手翻转"，一帧稳定 ~10µs，够稳；后续要更严可换双口 FIFO。
- 官方 `clk_wiz_0` 出 ≈12.3077MHz → fs≈48.08kHz（与官方例程一致）。
- 官方 I2C 配置链内部有分频时钟/异步复位——只在配置阶段跑，属复用官方、不改。
- mic1/mic2 具体落在哪一声道槽，靠上板捂麦实验定；反了就顶层交换。

## 6. 下一步（A1 通过后）
按接管路线：**VAD（语音活动检测）→ 双声道独立性确认 → TDOA 声源定位(LEFT/CENTER/RIGHT)**。双麦已在 mic1/mic2，硬件前提成立。
