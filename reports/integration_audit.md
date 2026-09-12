# 《EG4S20 Final Voice Robot Integration Audit》

日期：2026-09-09。只读审计，未修改任何 RTL/工程/约束文件。
审计范围：`rtl/` `rtl/audio/` `sim/` `sim/audio_sim/` `py/` `tools/` `data/` `reports/` `web/` `constr/` `TD_EG4_system/` `TD_EG4_top_audio/`。

四路并行子审计全部完成：
- V1 运动控制链（`top_system` 系）—— COMPLETE
- ES8388 音频采集链（`top_audio` 系）—— COMPLETE
- V2 语音识别 + 决策链（`top_voice_system` 系）—— COMPLETE
- 生态（sim 脚本 / web / py golden / tools / data / reports）—— 由主工程师直接补审完成

---

## A. 当前工程树（关键文件）

```
E:\electronic-circuit\
├── rtl/                        # 全部 RTL（两工程共享同一目录）
│   ├── top_system.v            # V1 顶层：矩阵键盘→target→FSM→轨迹→PID→电机→UART[AA]
│   ├── top_audio.v             # A1 顶层：ES8388 config + I2S + pcm_bridge + energy/vad/status
│   ├── top_voice_system.v      # V2 骨架顶层（feature_engine 输入=0，ES8388 未接，不可上板）
│   ├── audio/                  # clk_wiz_0(PLL) es8388_config i2c_dri i2c_reg_cfg
│   ├── (V1 积木) clock_enable uart_tx uart_rx keypad_scan target_input
│   │            state_machine trajectory_planner pid_controller virtual_motor
│   │            fault_detector seven_seg beep_gen switch_input led_ctrl uart_telemetry
│   ├── (音频积木) audio_pcm_bridge audio_energy audio_vad audio_status audio_rpt
│   ├── (V2 积木) pre_emph front_wind front_chain fft_core mel_bank log2_lut
│   │            logmel_chain dct2_mfcc feature_engine mfcc_quant
│   ├── (V2 决策) vtmpl speaker_verify utter_vote cmd_matcher cmd_vote
│   │            decision_fsm motion_plan ctl_chain telemetry_voice
├── constr/                     # top_system.adc / top_audio.adc（两套 .adc 均存在）
├── TD_EG4_system/TD_EG4_system.al   # V1 TD 工程（13 RTL + top_system.adc，TOP=top_system）
├── TD_EG4_top_audio/top_audio.al    # A1 TD 工程（12 RTL + top_audio.adc，TOP=top_audio）
├── sim/                        # V1 TB + 全部 V2 语音 TB（但 modelsim.do 只跑 V1）
├── sim/audio_sim/              # 音频 sim 工作目录 + 全部 .mem golden 系数表
├── data/                       # commands/cmd_{stop,left,right,forward}.mem + cmd_0..3.mem、
│   │                           # speaker/owner_template.mem、speaker_features/*.npz(39 文件)
├── py/ tools/                  # Python golden(frontend/audio_golden) + 离线工具链 + CAM++(PC only)
├── web/                        # 数字孪生 index.html+style.css+app.js（DEMO/LIVE，无框架）
└── reports/                    # speaker_verification/、comparison_summary(LOO A/B)、ROC/DET png
```

---

## B. 模块依赖图（目标最终数据流 + 现状标注）

```
ES8388 (codec master, I2C addr=0x11)                      [A1 板级 PASS]
  ├─ aud_mclk ← clk_wiz_0(C1=12.3077MHz, PLL from 50MHz)  [A1 板级 PASS]
  ├─ I2C      ← es8388_config→i2c_reg_cfg→i2c_dri          [A1 板级 PASS]
  └─ I2S      → audio_pcm_bridge  (aud_bclk域→sys_clk域CDC) [A1 板级 PASS]
                   │ pcm_l/r[23:0] signed + pair_valid(~48k, sys_clk域)
                   ├─→ audio_vad (VAD, 门控/起停)          [A1 板级 PASS 但阈值需重测]
                   │     └─ TH_ON/TH_OFF 需实测(静音/说话)  ← 阶段3任务
                   └─→ audio_energy (可选, 方向/显示)
   ▼ 缺一块胶水(阶段3新模块) v2_feature_glue:
      L声道选择 + 64采样/帧 + frame_start + pcm_valid + VAD门控 + busy背压
feature_engine (N=64 hop=64 NB=33 M=20 K=13 PS=22)        [sim PASS; 板上未综]
  ├── pre_emph→front_wind(Hann Q15)→fft_core(Q15 tw)→power(>>22)
  ├── mel_bank(CFQ12)→log2_lut→dct2_mfcc(DQ12)→int16
  ├── feature_valid/feature_index[0..12]/feature_data(int16)/frame_done
  ├─→(Who)  speaker_verify(vtmpl L1,TH=5000占位)→utter_vote(8帧/5)→owner_valid
  └─→(What) cmd_matcher(4×vtmpl argmin)→cmd_vote(8帧多数)→cmd_id(0停1左2右3前)
        ▼
decision_fsm: o_cmd_valid = owner_valid && cmd_decision_valid
  → o_cmd_action (0停/2前/3左/4右)
        ▼
action→{target,start} 映射 (前→90° 左→0° 右→180° 停→freeze)    ← V2 骨架内联
        ▼
[V1 复用不变] state_machine?/trajectory_planner→pid_controller→virtual_motor→pos
        ▼
uart_telemetry([AA][state][tgt][pos][chk])  ← V1 原格式必须保留(web 不退化)
voice 附加帧([AB]...可选)                    ← 阶段9设计, 需同步改 web parser
        ▼
web Twin (TelemetryParser 现只认 0xAA/5字节/state≤4)
```

### 关键“现有证据不一致/缺失”清单（全部实测代码，非推测）

1. `telemetry_voice.v` **不能直接发给现有 Web**：第 2 字节被塞成
   `{owner,cmd_id,action}`（如 owner=1/cmd=3/act=2 → 0xE8=232），而 `web/app.js` 的
   `onTelemetry` 对 `state>4` 直接丢弃整帧 → **Live 模式会“冻结/无更新”**。必须保留
   `[AA][state0..4][tgt][pos][chk]` 作主运动帧，语音字段另设帧头(0xAB 等)或改 web parser。
2. `feature_engine` 输入在 `top_voice_system` 里全接 0：`frame_start=0,pcm_valid=0,
   pcm_data=0` → 引擎永不启动（S_WAIT）。这是**骨架未上板**的根本原因，不是模块缺陷。
3. `speaker_verify` 在骨架里 **TPL 未覆盖**，默认 `"data/spk_tpl.mem"` 在仓库根不存在；
   真实模板在 `data/speaker/owner_template.mem`（13 行 int16 hex4，11 条注册均值）。
4. KWS 模板存在两套命名：`data/commands/cmd_stop/left/right/forward.mem`（骨架真正接线）
   与 `cmd_0..3.mem`。**需定一套为规范**，否则数据口径会漂移。
5. 系数 ROM 表 `hann_64/tw_re/tw_im/mel_coef/log2_lut/dct_basis .mem` **只在
   `sim/audio_sim/data/`**，由子模块 `$readmemh` 相对路径加载。sim 必须以
   `sim/audio_sim` 为工作目录；**板上综合(TD)是否支持 `$readmemh` 初始化 ROM 是头号风险**，
   `top_voice_system` 从未综合过，没人验证过这一点。
6. `audio_pcm_bridge` 的 `pcm_l/r` 声明为 `reg`(unsigned) 但内容是 24bit 补码 → 接
   feature_engine(signed) 需显式 `$signed()`，避免符号解释不一致。
7. 声纹真实情况(诚实)：`reports/speaker_verification` 实测 owner/impostor 帧级 L1
   **分布几乎完全重叠**（owner mean 3369±2069 / imp 3385±2033），帧级不可分；
   录音级也重叠。TH=5000 是占位。**不能宣称可靠；必须用真实 ES8388 采集重训/重测。**
8. `top_voice_system` 不用 `state_machine`，用裸 `move` 标志 → 没有 HOLD/FAULT 语义，
   也没有 0..4 的 state 喂 UART。最终应让语音命令走 `target_valid+start` 进入同一
   `state_machine`（保留故障/到位语义），而不是旁路它。

---

## C. 最终架构图（建议，与 §B 一致）

推荐唯一顶层 **`top_voice_robot`**，工程目录 **`TD_EG4_voice_robot/`**（.al + 合并 .adc）。
内部建议拆：
```
top_voice_robot
├── (audio)     clk_wiz_0 + es8388_config + audio_pcm_bridge      [从 top_audio 原样迁]
├── (front)     audio_vad + v2_feature_glue(新) → feature_engine  [新胶水 + 复用量]
├── (who)       speaker_verify(TPL→owner_template) + utter_vote
├── (what)      cmd_matcher(TPL→data/commands 规范名) + cmd_vote
├── (decision)  decision_fsm   (legacy in_vad/auth/dir 可接 VAD 或留 0)
├── (motion)    输入仲裁(键盘/语音)→target_valid+start→state_machine
│               →trajectory_planner→pid_controller→virtual_motor→fault_detector
├── (periph)    seven_seg + led + beep_gen(按键与语音反馈)
├── (telemetry) uart_telemetry[AA 主帧不变] + (阶段9) 0xAB 语音调试帧
└── (perception 显示) L/R 能量、direction(双麦差, 阶段9后)
```
键盘与语音是**两个并行输入源**，后端共用 V1 运动链（原则 §13：语音只是新输入源）。

---

## D. 文件迁移表

| 动作 | 文件 | 依据 |
|---|---|---|
| 原样复用 | clock_enable seven_seg beep_gen uart_tx uart_rx switch_input | V1 验证过 |
| 原样复用 | trajectory_planner pid_controller virtual_motor fault_detector | V1 板级 PASS，接口不再动 |
| 原样复用 | state_machine（最终接回，供语音走 target_valid+start） | V1 验证过 |
| 原样复用 | audio/clk_wiz_0 es8388_config i2c_dri i2c_reg_cfg | A1 板级 PASS，0x11/引脚不可动 |
| 原样复用 | audio_pcm_bridge audio_vad audio_energy | A1 板级 PASS（阈值待重测） |
| 原样复用 | pre_emph front_wind front_chain fft_core mel_bank log2_lut logmel_chain dct2_mfcc feature_engine mfcc_quant | B3/B4 逐位验证过，参数锁定 |
| 原样复用 | vtmpl speaker_verify utter_vote cmd_matcher cmd_vote decision_fsm motion_plan | TB 已写、仿真过(非板级) |
| 需改接口 | speaker_verify 调用点补 TPL=`data/speaker/owner_template.mem` | 现默认路径不存在 |
| 需改接口 | audio_pcm_bridge pcm_l/r 输出处 $signed()（或顶层转换） | 声明 unsigned/内容补码 |
| 需改接口 | feature_engine 的 .mem 加载路径/初始化方式在 TD 综合下确认 | 头号风险 |
| 需改接口 | telemetry_voice → 保留 [AA][state..] 主帧；语音字段另议 | web parser 硬约束 |
| 需新建 | v2_feature_glue（bridge→feature_engine 帧控制器） | 桥与引擎无直接接口 |
| 需新建 | 输入仲裁（键盘 + 语音 action → target_valid/start/go/stop） | 双输入源汇聚 |
| 需新建 | top_voice_robot.v（唯一最终顶层） | 见 §I |
| 需新建 | TD_EG4_voice_robot/.al + constr/top_voice_robot.adc（合并两套） | 最终 TD 工程 |
| 弃维护 | 不再维护三套独立顶层做“当前版”；保留 top_system.al/top_audio.al 供回归 | §11 |

---

## E. 接口迁移表（关键交接面）

| 交接面 | 源→目标 | 现状 | 处理 |
|---|---|---|---|
| PCM 域 | audio_pcm_bridge → feature_engine | bridge 给 `pair_valid`(每立体声对 1 脉冲)；引擎要 `pcm_valid`(每采样)+`frame_start`(每 64) | v2_feature_glue：取 L，计 64 pair_valid，帧首拉 frame_start，back-pressure 用 busy |
| 特征域 | feature_engine → speaker_verify/cmd_matcher | `feature_valid+feature_index[3:0]+feature_data[15:0]` 已一致（骨架已并行接线） | 只需真实喂入 |
| 模板域 | vtmpl TPL 参数 | speaker 用错路径；cmd 用 ../../data/commands/* | 统一到相对工作目录可解析的规范路径 + 真实 owner 模板 |
| 帧投票 | utter_vote→decision_fsm / cmd_vote→decision_fsm | owner_valid / decision_valid+cmd_id 已一致 | 保留 |
| 决策域 | decision_fsm → motion | 骨架内联 action→target 映射；可保留 | 最终接 state_machine 的 target_valid/start |
| 遥测域 | top → uart_telemetry | V1 [AA][state][tgt][pos][chk] | 主帧**原样保留**；语音字段另加帧头(0xAB)或同步改 web |

---

## F. IO / ADC 冲突检查

（依据两份 .adc 审计结果；最终 top_voice_robot.adc = 两套并集，逐项复核）

| 共享/复用 | 引脚 | 说明 |
|---|---|---|
| sys_clk | R7 | 两工程同用 50MHz，无冲突 |
| sys_rst_n | A9 | 同用 |
| tx (UART) | D12 | 同用 |
| led[0..7] | B14 B15 B16 C15 C16 E13 E16 F16 | 同用（最终分配需重定语义） |
| seg/dig_cs/row/col/fault_sw/buzzer | A4..H11 组 | 仅 system 用 |
| aud_mclk | N5 | 仅 audio 用（J0 音频座） |
| aud_bclk | M6 | 仅 audio 用 |
| aud_lrc | M7 | 仅 audio 用 |
| aud_adcdat | R14 | 仅 audio 用（ES8388 ASDOUT→FPGA） |
| aud_scl | R12 | 仅 audio 用 |
| aud_sda | R9 | 仅 audio 用（inout） |

**结论**：ES8388 六根音频引脚在独立 J0 座区，与键盘/7段/LED/UART **不重叠**；共享的仅
clk/rst/tx/LED 这类“本就该共享”的 IO。合并 .adc 无电气冲突。**ES8388 I2S_DI/DO 方向与
I2C 0x11 保持已验证事实，不重查。**
注意：`top_system` 用满 33 IO(6.7%)、`top_audio` 17 IO；合并后 LED 复用作状态灯，IO 余量
充足（188 可用）。

---

## G. Clock / PLL 检查

| 时钟 | 来源 | 频率 | 域 | 冲突 |
|---|---|---|---|---|
| sys_clk | R7 晶振 | 50 MHz | 全部逻辑主域 | 无 |
| aud_mclk | PLL C1(clk_wiz_0) | 12.3077 MHz | 仅 ES8388 MCLK pad | 无 |
| aud_bclk | ES8388(master) | ~2.3 MHz | 仅 pcm_bridge 内部 | 无 |
| dri_clk | i2c_dri 内部分频+BUFG | ~1 MHz | 仅 I2C 状态机 | 无 |

EG4S20 有 4 个 PLL；最终只需 1 个。无分频寄存器时钟新引入。共享 sys_clk 50MHz，1ms tick
用 clock_enable。**无 Clock/PLL 冲突。**

---

## H. Resource / Timing 风险

现状（TD 日志实测）：
- V1 top_system：LUT 1323(6.8%) FF 303 DSP 3(10%) BRAM 0 PLL 0 IO 33
- A1 top_audio：LUT 906(4.6%) FF 547 PLL 1 IO 17；0 DSP/BRAM
- 两者均无 SDC → Fmax 无有效约束值（WNS=INT_MAX 假值）。**最终工程应补 .sdc。**

预估与头号风险：
1. **ROM 系数表能否综合**（`$readmemh` 初始化在 TD 下 → BRAM/分布式 ROM）。hann/tw/
   mel/log2/dct/模板合计约几百行常数，LUT-ROM 或 BRAM 皆可，但**从未在板上验证**——这是
   语音链能不能上板的总闸。资源量级小（估 <1~2 BRAM 或 <1k LUT），不是瓶颈，瓶颈是“TD 支不支持”。
2. FFT/mel/dct 的 64bit 乘加在 50MHz 顺序展开，Fmax 应安全；但 DCT 输出 32bit + mel 64bit
   加宽需留意无 SDC 时布线。真正时序风险低。
3. 实时节奏：帧=64 采样@48k=1.33ms=66,667 周期@50M；引擎要在帧间完成整条 FFT→DCT，
   glue 需处理 busy（若引擎未就绪则跳帧，投票变慢但不崩）。这是**功能节奏**风险。
4. 声纹/KWS 判别力：**这是最大“有效性”风险**。板上需用真实 ES8388 采集（静音/命令/
   陌生人）重定 VAD 阈值 + 重训 speaker 模板 + 数据驱动定 TH，不能拍脑袋（§5/§38 原则）。

---

## I. Integration Roadmap（阶段顺序，可独立观察）

| 阶段 | 内容 | 验收 |
|---|---|---|
| 0 | 本审计 | 只读，输出本文档 |
| 1 | top_voice_robot 建立 + V1 运动回归（TEST_CMD 注入 + 键盘并存） | SIM PASS；键盘功能不退化 |
| 2 | ES8388 config/PLL/I2S/pcm_bridge 原样迁入 → 真实 PCM | 板级 A1 复验(P≈48k/LR/24bit) |
| 3 | VAD + 帧胶水(v2_feature_glue) + feature_engine 真实 PCM | 静音/说话能量、diff=0 校验 |
| 4 | feature_engine 板级(MFCC vs audio_golden) | diff=0/容差；ROM 综合打通 |
| 5 | speaker_verify 接入 + 真实模板/阈值重定 | 板上 owner/stranger 数据 → TH |
| 6 | cmd_matcher 接入 4 命令 | 4 命令 KWS 板上数据 |
| 7 | Who+What → decision_fsm → state_machine/motion | 测试矩阵(§41)过 |
| 8 | UART [AA] 主帧回归 + (0xAB) 语音帧 | web Live 正常 + 语音可见 |
| 9 | 双麦方向(能量差) | LEFT/RIGHT/CENTER 演示 |
| 10 | 全链 Web 最终演示 + 端到端延迟 + 资源报告 | 真实闭环 |

**建议先决子项（阶段1内嵌）**：验证 TD 对 `$readmemh` ROM 的综合支持（拿最小 fe 单一模块
试综合），这决定 4 阶段之前是否需给系数 ROM 换初始化写法。

---

## J. 第一阶段具体修改计划（Phase 1 提案）

目标：建立唯一顶层 `top_voice_robot`，先只验证 **V1 运动链全复用 + 新顶层 → [AA] 遥测**，
键盘功能不退化；语音以 TEST_CMD 注入暂代。

拟改动（小步、可回退）：
1. **新建 `rtl/top_voice_robot.v`**：
   - 原样例化 V1 全套：clock_enable/keypad_scan/target_input/state_machine/trajectory_planner/
     pid_controller/virtual_motor/fault_detector(按 top_system 现有接法)/seven_seg/beep_gen×3/
     uart_telemetry → tx/seg/dig/led/buzzer 引脚同 V1。
   - 增加 `TEST_CMD[2:0]` + `test_cmd_valid` 注入口：映射到同一
     {target(0/90/180), start} 路径，与键盘并行走同一 state_machine。
   - UART 仍 `[AA][state][tgt][pos][chk]`（state 来自 state_machine）→ Web Live 与 V1 一致。
2. **新建 `sim/tb_top_voice_robot.v`**：跑 FORWARD/LEFT/RIGHT/STOP 四命令驱动运动链 +
   抓 [AA] 帧，断言 target/pos/state 正确；并保留 tb_top_system 回归。
3. **不改任何已验证模块文件**；不建新 TD 工程前先用 ModelSim 全量回归
   （`sim/modelsim.do` + 新增 top_voice_robot TB）。
4. 同步验证 Web `window.__twin.runSelfTests()` 对该顶层的 [AA] 帧不回归。

风险：低——新顶层只是“V1 逻辑 + 一个测试命令寄存器 + 同样遥测”，所有改动都是新增端口/新增文件。
验证：ModelSim 回归（V1 全部 TB + 新 TB）+ （若可用）TD 综合/布线/资源报告；板级由你烧录复验。

### 最终工程命名
工程目录 `TD_EG4_voice_robot/`，顶层 `top_voice_robot`。`TD_EG4_system` 与 `TD_EG4_top_audio`
保留，仅作回归参考。

---
*本审计只读完成；下一步按 §J 进入 Phase 1，需你确认。*
