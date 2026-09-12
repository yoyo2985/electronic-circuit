# 基于 FPGA 的虚拟机器人实时感知、决策与闭环运动控制系统（EG4S20）

真实 FPGA 控制器（安路 EG4S20BG256 开发板）+ 虚拟物理对象（虚拟电机/编码器）+ PC 数字孪生的闭环验证平台。核心思想：在资源受限 FPGA 上把**语音感知 → 身份认证 → 指令理解 → 运动决策 → 执行反馈**全链路硬件化，实现“主人语音输入 → FPGA 实时处理 → 身份验证 → 指令解析 → 电机控制 → 数字孪生反馈”的完整闭环。

> 项目定位不是“高精度语音识别算法”，而是**面向具身智能机器人的 FPGA 实时感知-决策-控制闭环验证平台**：验证资源受限 FPGA 上把感知、决策、执行串成闭环的可行性，语音模块采用轻量级原型算法。

Verilog HDL / TangDynasty(TD) / ModelSim / Python(PyAV+NumPy, 仅 Golden/工具/离线，不作实时替代)。

📦 GitHub 仓库：[`yoyo2985/electronic-circuit`](https://github.com/yoyo2985/electronic-circuit)（课程报告 `report.tex`/`report.pdf` 同步维护于此）

## 系统架构（四层）

```text
┌─ 感知层（Perception）────────────────────────────────────────┐
│  ES8388 → I2S → PCM(24bit 双声道) → VAD → MFCC(13-D)         │
├─ 认知层（Who + What）────────────────────────────────────────┤
│  speaker_verify 声纹验证(主人身份) + cmd_matcher 关键词匹配     │
├─ 决策控制层（Decision）───────────────────────────────────────┤
│  decision_fsm → state_machine(IDLE/READY/MOVE/HOLD/FAULT)     │
│  → trajectory_planner 轨迹限速 → pid_controller 位置环 PID     │
├─ 执行与验证层（Actuation）────────────────────────────────────┤
│  virtual_motor 虚拟电机(一阶惯性+位置积分+限位) → 编码器反馈    │
│  → UART 遥测 → PC 数字孪生(Web 上位机实时显示目标/位置/状态)     │
└──────────────────────────────────────────────────────────────┘
```

V1 运动链（键盘输入，语音缝与运动链同构复用）：

```text
EG4S20 FPGA
  Input(键盘/拨码) → 目标输入 → 状态机 → 轨迹限速 → PID
       → 虚拟电机 → 故障检测
  侧路：数码管/LED 显示、UART 遥测 → PC 数字孪生
```

感知接口与控制算法解耦：输入来源可替换为传感器/语音，后端决策/轨迹/PID/虚拟执行器不变。语音命令（`decision_fsm` 输出 action）与键盘目标统一为 `target/valid/go` 进入同一运动状态机。

## 创新点

1. **FPGA 实时信号处理 + 机器人控制 + 数字孪生三者结合**，构建完整闭环验证平台——不依赖纯软件仿真，验证资源受限 FPGA 实现具身智能实时交互的可行性。
2. **感知—决策—执行链路全硬件化**：音频采集、特征提取、身份验证、指令识别、状态机、PID、虚拟电机在单一 FPGA 内流水线并行、固定周期运行。
3. **轻量级语音交互架构**：以主人声纹验证（Who）+ 有限词表关键词匹配（What）提高机器人交互安全性，适合封闭命令集的控制场景。

## 为什么用 FPGA（而非纯 CPU/软件）

- 机器人系统有**多源实时信号处理**需求（音频采集、特征提取、控制计算），FPGA 可流水线并行、固定周期运行，实时性与确定性不受操作系统调度影响。
- 相比现成语音模块的**黑盒识别**，本方案从音频采集、特征提取到决策控制全部在 FPGA 内部**可观察、可调试**（`[AB]` 语音调试帧逐项导出内部状态）。
- 相比深度学习模型：EG4S20 仅 ~19600 LUT，直接部署大型网络成本高；本方案用 MFCC+模板匹配的模块化轻量方案**验证系统架构**，后续可替换为量化 TinyML 模型。

## 资源占用（板上综合结果）

| 资源 | 占用 | 说明 |
|---|---|---|
| LUT | **6440 / 19600 = 32.9%** | 整体约 1/3，满足 EG4S20 部署要求 |
| FF | 1669 | |
| DSP | 28 / 29 | FFT/乘加密集处 |
| BRAM | 4 | FFT 缓存 + 模板 |
| PLL | 1 | |

关键优化：把 FFT 缓存从**寄存器阵列改为 BRAM IP**，FFT 部分 LUT 从 ~11620 降至 ~375，是资源能压到 33% 的主要原因。

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
| 08 | `target_input` | ✅ | ✅ | 键盘 0..180 目标输入，超限拒收；蜂鸣器三音反馈（top_target） |
| 09 | `virtual_motor` | ✅ | ✅ | 定点一阶电机+行程限位（top_motor 0↔180） |
| 10 | `pid_controller` | ✅ | ✅ | 位置环定点 PID+三限幅（top_pid SW 选 40°/120°） |
| 11 | `trajectory_planner` | ✅ | 整机内 | 限速参考轨迹（梯形近似，不超调） |
| 12 | `state_machine` | ✅ | 整机内 | IDLE/READY/MOVE/HOLD/FAULT |
| 13 | `fault_detector` | ✅ | 单测 | 堵转检测；整机 demo 用 SW2 手动故障演示（见下） |
| 14 | `top_system` | ✅ | ✅ | V1 运动全链 + 按键蜂鸣反馈 |
| 15 | `uart_telemetry` | ✅ | 整机内 | 遥测帧 `[AA][state][target][pos][chk]` |
| 16 | `tools/pc_twin.py` | – | 脚本 | PC 端数字孪生：实时打印/曲线 |
| 17 | DAC（加分） | – | – | 未实现（R-2R 复用 LED 脚，可选） |
| 18 | ES8388 语音感知链 | 见 V2 章节 | **板上链路 PASS** | I2S→PCM→VAD→MFCC→声纹→指令→决策，见下 |

> 注：板上自动堵转检测在低速/整数位粒度下易误判，整机演示中关闭自动堵转（模块已单测），故障演示通过 SW2 手动触发，报告可如实说明。

## 目录

- `rtl/`    源码（V1 运动 + V2 语音：audio_pcm_bridge/feature_engine/speaker_verify/cmd_matcher/seg_decide/decision_fsm/motion_plan 等）
- `rtl/audio/`  ES8388 官方配置链 + PLL 封装
- `sim/`    testbench（ModelSim）；`sim/audio_sim/` 语音 TB + 向量(data/)
- `constr/` 引脚约束 `.adc`（取自板卡官方例程，不臆造）
- `doc/`    设计规范/架构/接口/仿真指南 + B4/B5 规格
- `py/`     Python Golden：frontend/audio_golden(向量化)/gen_* 参考
- `tools/`  V1 数字孪生脚本 + V2 声纹工具链(audit/preprocess/build_template/evaluate) + audio_monitor
- `data/`   speaker/命令模板（真实语音与派生特征不入库）
- `reports/`  声纹/采集/固件审计报告（spk_th_data、board_bringup_cmdfix、vad_report 等）
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

## 板上整机演示

顶层两套，均走同一运动链：

- **V1 运动**：`top_system`（`constr/top_system.adc`），键盘输入目标 → 状态机 → 轨迹 → PID → 电机 → 遥测。
- **语音+运动统一顶层**：`top_voice_robot`（`constr/top_voice_robot.adc`），键盘与语音命令统一接入运动状态机，遥测 `[AA]` 主帧不变（Web 数字孪生不退化），另有 `[AB]` 语音调试帧（`VDBG_UART=1` 时）。

操作（V1 为例）：

1. **SW0 拨上** 释放复位（rst_n 低有效：SW0 下=复位、上=运行）。
2. 数码管显示当前位置(0~180)。
3. 输入目标：按 `KEY9`、`KEY0` →（内部记 90）；按 **KEY11(ENTER)** 启动。
   - LED0=目标已设；LED1=运动中；数码管平滑涨到 90；到位后 LED2=到位。
4. 故障演示（电机到位后）：**SW2 拨上** → LED3 亮、停；SW2 拨回 + **KEY10(CLR)** 复位。

按键约定：KEY0~9=数字，KEY10=CLR/ACK，KEY11=确认并启动。

按键蜂鸣反馈（无源蜂鸣器 `Buzzer_Out=H11`，由 `beep_gen` 方波驱动）：数字键=2kHz/80ms 短“嘀”、KEY10 清除=800Hz/150ms 低鸣、KEY11 确认=3kHz/120ms 高鸣，每次响完自动停止。

## 板上串口/遥测

- 板上 USB1=JTAG 下载；USB2=CH340 → PC 出现 COM 口。
- SSCOM/串口助手 115200,8,N,1 可收遥测帧（每 ~100ms 一帧 `AA …`）。
- 数字孪生：`python tools/pc_twin.py COM7 [--plot]`（依赖 pyserial；画图需 matplotlib）。
- 语音调试帧 `[AB]`：`AB 01 01 ...`（帧头 / VAD / MFCC 有效 / owner / cmd / score 等，16 项），用于验证语音链路内部状态。

## 🖥️ Web 数字孪生控制台（web/）

浏览器端的 **FPGA 机器人数字孪生 / 实时闭环监控平台**（原生 HTML/CSS/JS + Web Serial，无框架、无 npm 依赖）：

```
EG4S20 FPGA → UART 遥测帧 → Web Serial → 网页数字孪生
（真实控制器）                       （虚拟机器人/状态机/曲线/故障）
```

**数字孪生采用“模型驱动的实时状态映射”方法，而非商业物理引擎**（未引入 MuJoCo/Gazebo/Unity Physics）。核心是虚实映射 + 数据同步 + 模型反馈：

- **FPGA 端（真实控制器）**：状态机、PID、虚拟电机模型、编码器反馈模型。
- **PC 端（实时可视化）**：Web Serial 通信 + HTML/CSS/JS + SVG 机器人模型 + 实时曲线。
- **数据流**：FPGA 目标位置/实际位置/速度/状态 → UART → Web → 机器人姿态显示。

因为本项目研究的是机器人**控制器与感知决策闭环**，而非机械结构多体动力学，故采用 FPGA 内部简化动力学模型；数字孪生本身不要求复杂物理引擎。

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
   → mfcc_quant(16bit) → vtmpl/speaker_verify(Who 声纹)
   → cmd_matcher(What 关键词) → seg_decide(段级决策)
   → decision_fsm → motion_plan →(V1 虚拟电机/数字孪生)
```

| 阶段 | 交付 | 验证 |
|---|---|---|
| A1 采集 | `audio_pcm_bridge`(I2S 成帧跨时钟)、energy、status、top_audio | ModelSim PASS；**板上验收 PASS**：P≈24038=48k、真实双麦 24-bit、LED 左右声道独立响应 |
| B1/B0 | VAD 接入顶层；`py/frontend.py` Golden | PASS |
| B3 | pre_emph→front_wind(Q15Hann)→fft_core(N=64)→mel_bank→log2/logmel→dct2_mfcc | 各积木逐位/容差 PASS |
| B4 | `feature_engine`（N64/M20/K13/hop64，含 Power 级） | 全0/1kHz/随机 39 特征逐位 PASS |
| B5.2 | `mfcc_quant` 32→16（QS+饱和） | 极值 PASS |
| B5.3 | `speaker_verify`（feature→vtmpl DIM13） | 端到端 3 帧 PASS |
| B5.4-6 | 真实 m4a 工具链 + owner_template.mem | 见“诚实状态” |
| B5.7 | `utter_vote` 片段多数投票 | 7 极端场景 PASS |
| E1/E2 | `decision_fsm`/`motion_plan`/`ctl_chain` | 合成 PASS |
| E3+ | `cmd_matcher` + `seg_decide` 段级决策 + `top_voice_robot` 统一顶层 | 板上链路 PASS（见下） |

**统一定点参数**：帧/FFT=64、hop=64、power bins=33、mel=20、MFCC=13、PCM=24bit signed、48k、默认 L 声道(R 保留给方向)。Python Golden 与 RTL 用整数镜像逐位一致（`py/audio_golden.py` 与标量/引擎 diff=0）。

### 板上链路状态（2026-09-10，真实采集定标）

- **A1 板级采集验收 PASS（2026-09-09，top_audio）**：mic 模拟前端已通。根因是 10 脚散线版把模块 **I2S DI/DO 接反**——模块 H1 的 DI/DO 命名站在 FPGA 侧：`I2S_DI`=ES8388 ASDOUT(ADC 输出)→FPGA R14、`I2S_DO`=FPGA P6(DAC 输出)→ES8388 DSDIN；`.adc` 约束自始无误。换正后 R14 收到 codec 真实双麦 ADC 数据，`top_audio` LED 左右两组随 mic1/mic2 各自独立响应 → **双声道独立成立**（TDOA 前提）。PGA 已回落到官方默认 +6dB(0x22)（此前 +30dB 满幅削顶致 VAD/能量常饱和）。
- **cmd_id 恒 0 缺陷已修**（`reports/board_bringup_cmdfix.md`）：`cmd_matcher` 原把 4 个命令模板误写成字符串文件路径参数，综合后模板=路径 ASCII 字节 → 4 条 L1 几乎相等 → argmin 恒取 d0。已改为内嵌 208-bit 整数字面量（与 `speaker_verify` 同一口径），`tb_cmd_lit` 4/4 PASS。
- **声纹闸（Who）定标**：`SPK_TH=2500`（`reports/spk_th_data.md`）。属主“机器人 你好”组内最大 L1=1532，陌生人最小 L1=4487 → 阈值落在 [1532, 4487]，对属主关键词 ~1.6×、对陌生人 ~1.8× 裕量，**属主/陌生人可区分**。
- **段级决策（`seg_decide`）**：逐帧判定已废弃（owner/stranger 逐帧分布 3584~7424 完全重叠）；改段均值 L1 决策，`TH_OWN=4300`（属主全词段均值 max=4106 < 陌生人 min=4486）。

### 诚实状态（语音算法边界，如实记录）

- **命令判别（What）实测 argmin 命中率**：属主命令词 22/35 = **63%**；其中“前进”6/6 干净，“停止”4/5，左/右互混是主要误差源（左转 6/13 误判到右/停，右转 6/11 误判到左）。全 49 段 argmin 命中 45%。这是 13 维 MFCC 和 + L1 argmin 作为命令判别器的**天花板**，不是采集错误——`cmd_matcher` 即 argmin+8 帧多数决，板上表现接近该表。
- **单帧 vs 片段平均（鲁棒性根因）**：离线建模板用的是语音片段平均特征（属主片段平均距离 ~1500 内），而在线实时是段均值/单帧特征，受发音阶段、音量、停顿影响波动更大（实时单帧可到 3000+）→ 固定阈值会误拒。因此改段级决策（`seg_decide`）缓解，而非硬拍单帧阈值。
- **声纹闸只区分“属主 / 陌生人”，不区分“关键词 / 非关键词”**：属主说其它命令词到 owner 模板距离 <2500 也会过闸；后者是唤醒词/命令引擎的职责。
- **定位说明**：语音模块当前是**轻量级 MFCC+L1 模板匹配原型**，目标是验证 FPGA 端实时闭环架构的可行性，而非工业级语音识别。鲁棒性提升见下节“优化方向”。
- 原始语音 `sounds/` 与派生 `data/speaker_features/` 于最终交付清理时按隐私要求**删除**，`data/replay_pcm/`（回放 PCM）同步删除——报告插图 fig5/6/8/9 已固化入库无法重新生成；依赖这些数据的离线命令（`benchmark_ab.py`、`plot_golden_vs_rtl.py`、`plot_real_waveforms.py`）再跑会因缺数据报错，需重新采集后复现。

## 优化方向（后续工作）

1. **声纹模型**：L1 模板匹配 → 轻量化声纹 embedding（ECAPA-TDNN / 小 CNN），或量化后 TinyML/DS-CNN 部署到 FPGA。
2. **鲁棒性**：数据增强、噪声训练、多距离采样、音量归一化，覆盖不同距离/角度/环境。
3. **声源方向**：当前双麦能量比（`dir_energy`，L/R 能量比 >1.05× 判偏侧）→ 升级 TDOA 或神经网络声源定位。
4. **命令集**：有限词表 → 必要时扩展，保持 FPGA 资源可控。

## PC 端声纹算法评估（CAM++ vs MFCC 基线，离线参考）

- **导出模型**（ModelScope CAMPPlus → ONNX，动态帧轴）：
  `python tools/export_campplus_onnx.py` → `py/campplus/models/campplus_emb.onnx`（已 gitignore，模型不入库）。
  推理接口见 `py/campplus/interface.py`（`extract_embedding`/`verify_speaker`，192-D/L2/余弦）。
- **A/B 对比**（A=MFCC13+L1 录音级、B=CAM++ 余弦）两种模式：
  - `python tools/benchmark_ab.py --mode full` — 模板=全部 owner 均值（乐观参考）；
  - `python tools/benchmark_ab.py --mode loo` 或 `both`(默认) — **leave-one-out**：每轮留 1 条 owner 测试、其余 14 条均值做模板，impostor 对每轮模板对照；更接近真实泛化。
  - 输出 `reports/{comparison_campplus_vs_mfcc.csv, *_loo.csv, roc|det_comparison*.png, roc_loo_*.png, comparison_summary.txt}`
- **软件在环（无硬件）**：
  `python tools/sil_audio_controller.py --audio <命令m4a> --embedder mfcc|campplus`
- 结果（2026-09-08，数据样本少、模板含被评身份时乐观，需谨慎）：
  - full(模板=全 owner 均值): A(MFCC 录音级) EER≈0.000、B(CAM++) EER≈0.017
  - **LOO**: A EER≈0.000、B EER≈0.000（更接近泛化，但样本/内容高度相似，仍需扩数据复核）
  - 结论：CAM++ 区分明显优于帧级 MFCC 基线；B 结果来自 LOO/真实数据（详细见 `reports/comparison_summary.txt`）。

> 注意：该离线评估在**片段平均特征**上做，与板上**段级/单帧**判定口径不同——离线 EER 乐观，不能直接等同板级命令识别率（板级 63% 见“诚实状态”）。

### KWS 命令识别（并行 What 链，Who+What）

并行命令识别（不改 speaker/utter/feature_engine）：`feature_engine.MFCC → cmd_matcher(4×vtmpl L1) → cmd_vote(窗口众数) → cmd_id(0 stop/1 left/2 right/3 forward)`。决策= `owner_valid && cmd_valid → action(cmd_id)`，否则 IDLE。详见 `doc/voice_control_kws.md`。
- 命令模板：`python tools/gen_command_templates.py`（真实：`sounds/owner_sound/commands/<名>/*.{wav,m4a}`；能量 VAD 25ms/10ms，阈值=0.05×峰值，只取语音帧）→ `data/commands/cmd_<名>.mem`；
  无真实命令时仿真可用合成：`python py/cmd_golden.py`。
- 单测：`tb_cmd_matcher`、`tb_cmd_vote` 均与 Python 期望一致 PASS。
- **双引擎决策演示**（真实命令模板）：`sim/tb_voice_control.v` — 场景 A(owner+left→LEFT)、B(陌生人→不执行)、C(owner+stop→STOP) 端到端 PASS。
- **集成顶层** `rtl/top_voice_system.v`（TEST 注入/真实两模式）+ `telemetry_voice.v`；`rtl/top_voice_robot.v` 为**最终统一顶层**（键盘+语音命令缝 → 同一运动链，遥测 `[AA]` 主帧不退化）。

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
