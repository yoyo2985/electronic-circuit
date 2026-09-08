# 基于 FPGA 的虚拟机器人实时感知、决策与闭环运动控制系统（EG4S20）

真实 FPGA 控制器（安路 EG4S20BG256 开发板）+ 虚拟物理对象（虚拟电机/编码器）+ PC 数字孪生的闭环控制验证平台。采用“感知 → 决策 → 执行”闭环控制思想，构建机器人数字孪生与实时闭环控制验证平台。

**当前方向（V2，2026-09）**：在 V1 闭环运动基础上扩展 **ES8388 语音感知链**：双声道 PCM → VAD → 13-D MFCC 特征引擎(feature_engine) → 轻量声纹匹配(vtmpl/speaker_verify/utter_vote) → decision_fsm → 差分轮速，目标“主人声控的虚拟机器人”。ES8388 I2C 地址实测 **0x11**（官方例程 0x10 配不上）。硬件数字链路(48k I2S)已通；**mic 模拟前端待修**（见下“诚实状态”）。

Verilog HDL / TangDynasty(TD) / ModelSim / Python(PyAV+NumPy, 仅 Golden/工具/离线，不作实时替代)。

## 系统架构

```text
EG4S20 FPGA
  Input(键盘/拨码) → 目标输入 → 状态机 → 轨迹限速 → PID
       → 虚拟电机(速度一阶惯性 + 位置积分 + 限位) → 故障检测
  侧路：数码管/LED 显示、UART 遥测 → PC 数字孪生(上位机)
```

感知接口与控制算法解耦：输入来源将来可替换为传感器，后端决策/轨迹/PID/虚拟执行器不变。

## 模块与进度

| # | 模块 | 仿真 | 板级 | 备注 |
|---|---|---|---|---|
| 01 | `clock_enable` | ✅ | ✅ | 50MHz→tick_1ms（禁止造分频时钟） |
| 02 | `led_ctrl` | ✅ | ✅ | LED 心跳 + 跑灯（top_blink） |
| 03 | `seven_seg` | ✅ | ✅ | 4 位动态扫描数码管（top_seg 0~9999） |
| 04 | `switch_input` | ✅ | ✅ | 拨码采样（同步+消抖，top_sw SW→LED） |
| 05 | `keypad_scan` | ✅ | ✅ | 4×4 矩阵键盘，key_idx=丝印键号（top_key） |
| 06 | `uart_tx` | ✅ | ✅ | 115200，起始0+8位+停止1 |
| 07 | `uart_rx` | ✅ | ✅ | 经板上 CH340→COM7 双向实测 |
| 08 | `target_input` | ✅ | ✅ | 键盘 0..180 目标输入，超限拒收（top_target） |
| 09 | `virtual_motor` | ✅ | ✅ | 定点一阶电机+行程限位（top_motor 0↔180） |
| 10 | `pid_controller` | ✅ | ✅ | 位置环定点 PID+三限幅（top_pid SW 选 40°/120°） |
| 11 | `trajectory_planner` | ✅ | 整机内 | 限速参考轨迹（梯形近似，不超调） |
| 12 | `state_machine` | ✅ | 整机内 | IDLE/READY/MOVE/HOLD/FAULT |
| 13 | `fault_detector` | ✅ | 单测 | 堵转检测；整机 demo 用 SW2 手动故障演示（见下） |
| 14 | `top_system` | ✅ | ✅ | 键盘目标→状态机→轨迹→PID→电机→故障→遥测全链 |
| 15 | `uart_telemetry` | ✅ | 整机内 | 遥测帧 `[AA][state][target][pos][chk]` |
| 16 | `tools/pc_twin.py` | – | 脚本 | PC 端数字孪生：实时打印/曲线 |
| 17 | DAC（加分） | – | – | 未实现（R-2R 复用 LED 脚，可选） |
| 18 | ES8388 语音感知 | 见上 V2 章节 | 数字通/mic 待修 | 不再“未实现”，见 V2 语音感知链 |

> 注：板上自动堵转检测在低速/整数位粒度下易误判，整机 `top_system` 演示中关闭自动堵转（模块已单测），故障演示通过 SW2 手动触发，报告可如实说明。

## 目录

- `rtl/`    源码（V1 运动 + V2 语音：audio_pcm_bridge/feature_engine/speaker_verify/utter_vote/decision_fsm/motion_plan 等）
- `rtl/audio/`  ES8388 官方配置链 + PLL 封装
- `sim/`    testbench（ModelSim）；`sim/audio_sim/` 语音 TB + 向量(data/)
- `constr/` 引脚约束 `.adc`（取自板卡官方例程，不臆造）
- `doc/`    设计规范/架构/接口/仿真指南 + B4/B5 规格
- `py/`     Python Golden：frontend/audio_golden(向量化)/gen_* 参考
- `tools/`  V1 数字孪生脚本 + V2 声纹工具链(audit/preprocess/build_template/evaluate) + audio_monitor
- `data/`   speaker 模板/划分（真实语音与派生特征不入库）
- `reports/speaker_verification/` 声纹基线报告/CSV/审计
- `web/`    浏览器数字孪生控制台（Web Serial，见下）

## 快速开始（仿真）

ModelSim 逐个跑（在 `sim/` 下）：

```bash
vlib work
vlog ../rtl/clock_enable.v ../rtl/led_ctrl.v ... ../rtl/top_system.v   # 全部源文件
vlog tb_xxx.v ...                                                       # 对应测试台
vsim -c work.tb_xxx -do "run -all; quit -f"
```

也可用提供的 `sim/modelsim.do` 一次性编译；因为 `quit -sim` 语义，建议逐个 vsim 运行各 TB（见 `doc/final_guide.md`）。

## 板上整机演示（top_system）

工程源文件：见 `doc/final_guide.md`。顶层 `top_system`，引脚见 `constr/top_system.adc`。

操作：

1. **SW0 拨上** 释放复位（rst_n 低有效：SW0 下=复位、上=运行）。
2. 数码管显示当前位置(0~180)。
3. 输入目标：按 `KEY9`、`KEY0` →（内部记 90）；按 **KEY11(ENTER)** 启动。
   - LED0=目标已设；LED1=运动中；数码管平滑涨到 90；到位后 LED2=到位。
4. 故障演示（电机到位后）：**SW2 拨上** → LED3 亮、停；SW2 拨回 + **KEY10(CLR)** 复位。

按键约定：KEY0~9=数字，KEY10=CLR/ACK，KEY11=确认并启动。

## 板上串口/遥测

- 板上 USB1=JTAG 下载；USB2=CH340 → PC 出现 COM 口。
- SSCOM/串口助手 115200,8,N,1 可收遥测帧（每 ~100ms 一帧 `AA …`）。
- 数字孪生：`python tools/pc_twin.py COM7 [--plot]`（依赖 pyserial；画图需 matplotlib）。

## 🖥️ Web 数字孪生控制台（web/）

浏览器端的 **FPGA 机器人数字孪生 / 实时闭环监控平台**（原生 HTML/CSS/JS + Web Serial，无框架、无 npm 依赖）：

```
EG4S20 FPGA → UART 遥测帧 → Web Serial → 网页数字孪生
（真实控制器）                       （虚拟机器人/状态机/曲线/故障）
```

- **Demo Mode**：无 FPGA 也能完整演示（运动模型与 RTL 同构：轨迹限速 → P 反馈 → 一阶虚拟电机），内置
  `0→90 · 90→150 · 150→30 · 0→180` 四个实验与 RUN DEMO LOOP。
- **Live FPGA Mode**：浏览器 Web Serial 直连板上 CH340 串口（COM 口 + 115200 8N1），实时接收
  遥测帧 `[AA][state][target][pos][chk]`，驱动 SVG 机械臂（实心=实际，虚线圆环=目标）、状态机
  （IDLE/READY/MOVE/HOLD/FAULT）、Target/Actual/Error/Velocity 滚动曲线、故障横幅与事件日志。
- 通信超时（2 s 无帧）以**通信告警**单独提示，与机器人 FAULT 区分；Live 不伪造 FPGA 未发送的数据。

本地运行：

```bash
cd web
python -m http.server 8000     # 浏览器打开 http://localhost:8000（需 Chrome/Edge）
```

> Web Serial 仅支持 Chrome/Edge 且要求 localhost 或 HTTPS；Live 连接前 FPGA 需已在发遥测。
> 详细使用说明 / 遥测协议 / 常见问题见 **`web/README.md`**。

## V2 语音感知 / 声纹认证链（2026-09，独立于 V1 持续开发）

```
ES8388 → I2S(PCM 24bit L/R) → VAD → feature_engine(13-D MFCC)
   → mfcc_quant(16bit) → vtmpl/speaker_verify → utter_vote(owner_valid)
   → decision_fsm → motion_plan(VL/VR) →(V1 虚拟电机/数字孪生)
```

| 阶段 | 交付 | 验证 |
|---|---|---|
| A1 采集 | `audio_pcm_bridge`(I2S 成帧跨时钟)、energy、status(`Pxxxx Lxxxx Rxxxx Vx`)、top_audio | ModelSim PASS；板上数字链路通(P≈24038) |
| B1/B0 | VAD 接入顶层；`py/frontend.py` Golden | PASS |
| B3 | pre_emph→front_wind(Q15Hann)→fft_core(N=64)→mel_bank→log2/logmel→dct2_mfcc | 各积木逐位/容差 PASS |
| B4 | `feature_engine`（N64/M20/K13/hop64，含 Power 级） | 全0/1kHz/随机 39 特征逐位 PASS |
| B5.2 | `mfcc_quant` 32→16（QS+饱和） | 极值 PASS |
| B5.3 | `speaker_verify`（feature→vtmpl DIM13） | 端到端 3 帧 PASS |
| B5.4-6 | 真实 m4a 工具链(`tools/audit|speaker_preprocess|build_speaker_template|evaluate`) + owner_template.mem | 见“诚实状态” |
| B5.7 | `utter_vote` 片段多数投票 | 7 极端场景 PASS |
| E1/E2 | `decision_fsm`/`motion_plan`/`ctl_chain` | 合成 PASS |

**统一定点参数**：帧/FFT=64、hop=64、power bins=33、mel=20、MFCC=13、PCM=24bit signed、48k、默认 L 声道(R 保留给方向)。Python Golden 与 RTL 用整数镜像逐位一致（`py/audio_golden.py` 与标量/引擎 diff=0）。

### 诚实状态
- ES8388 数字链路正常(48k I2S、I2C 地址 0x11)；**mic 模拟前端无有效输入**（已试输入选择 0x00/0x50/差分+PGA24dB 等，待修/待原理图）。
- **B5.4-6 结论**：MFCC13+L1+mean 基线在内容高度相似的真实 m4a 上 **owner/impostor 帧级与录音级均不可分**（如实，不推荐上线、不用拍脑袋阈值）；`TH=5000` 仅占位。待 B5.7 投票(已完成结构) + 更稳前端/受控录制后再评估。
- 原始语音 `sounds/` 与派生 `data/speaker_features/` 已 gitignore（隐私/体积）。



## PC 端声纹算法评估（CAM++ vs MFCC 基线）

- **导出模型**（ModelScope CAMPPlus → ONNX，动态帧轴）：
  `python tools/export_campplus_onnx.py` → `py/campplus/models/campplus_emb.onnx`（已 gitignore，模型不入库）。
  推理接口见 `py/campplus/interface.py`（`extract_embedding`/`verify_speaker`，192-D/L2/余弦）。
- **A/B 对比**（A=MFCC13+L1 录音级、B=CAM++ 余弦）两种模式：
  - `python tools/benchmark_ab.py --mode full` — 模板=全部 owner 均值（乐观参考）；
  - `python tools/benchmark_ab.py --mode loo` 或 `both`(默认) — **leave-one-out**：每轮留 1 条 owner 测试、其余 14 条均值做模板，impostor 对每轮模板对照；更接近真实泛化。
  - 输出 `reports/{comparison_campplus_vs_mfcc.csv, *_loo.csv, roc|det_comparison*.png, roc_loo_*.png, comparison_summary.txt}`
- **软件在环（无硬件）**：
  `python tools/sil_audio_controller.py --audio <命令m4a> --embedder mfcc|campplus`
- 当前结果（2026-09-08，注意乐观性：模板含被评身份 + 每说话人仅 15/24 条录音）：
  A(MFCC 录音级) EER≈0.000（乐观）、B(CAM++) EER≈0.017、B owner cos 0.90–0.99 vs impostor 0.78–0.94，**CAM++ 区分明显优于帧级 MFCC 基线**。



## 设计规范要点（详见 `doc/design_rules.md`）

- 单一 50MHz 主时钟 + clock enable；禁止用寄存器生成分频时钟。
- 统一同步复位 `rst_n` 低有效。
- 时序用 `<=`；组合用 `always @(*)`/`assign`。
- 所有时间参数 parameter 化（仿真改小加速）。
- PID/电机定点整数运算：中间量一律 64 位有符号，避免无符号取负/窄参数移位截断/端口位宽高位成 Z 等 Verilog 陷阱。

## 板卡与工具

- 芯片 EG4S20BG256（19600 LUT，50MHz，CLK=R7）。
- 约束文件为 `.adc`（Tcl），语法与引脚均取自板卡官方例程（`_extract_basic`，不入库）。
- TangDynasty 5.6.5 / ModelSim ASE 10.3c。
