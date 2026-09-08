# Web 数字孪生控制台 · web/

基于浏览器的 FPGA 虚拟机器人**数字孪生实时监控/控制平台**（`index.html` + `style.css` + `app.js`，无框架、无 npm 依赖）。

```
                ┌──────────────┐
                │  Web Browser │  Digital Twin / HMI
                └──────┬───────┘
                       │  Web Serial API
                       │  (USB/COM → 浏览器)
                ┌──────▼───────┐
                │  EG4S20 FPGA │  Real-time Controller
                │   top_system │  (UART 遥测, ~10 Hz)
                └──────────────┘
```

> 本页不是"串口数据显示页"，而是把 FPGA 闭环控制系统同步到浏览器：网页上的机器人姿态、状态机、曲线全部由 **FPGA 真实遥测帧**驱动（Live 模式）；没有 FPGA 时用与 RTL 同构的仿真模型运行（Demo 模式）。

---

## 1. 系统简介

| 区块 | 作用 |
|---|---|
| 顶部状态栏 | 模式（DEMO / LIVE FPGA）、链路状态（CONNECTED / DISCONNECTED / TIMEOUT） |
| VIRTUAL ROBOT | 2D SVG 单关节机械臂数字孪生：**实心臂 = 实际位置**，**虚线臂 + 圆环 = 目标位置**，0~180° 量程刻度，带运动轨迹淡影 |
| 读数卡 | TARGET / ACTUAL / ERROR / VELOCITY（速度仅模型或估算，见 §8） |
| SYSTEM STATUS | 状态机可视化 IDLE→READY→MOVE→HOLD + FAULT 分支、当前状态高亮 |
| FPGA LINK | 端口、包计数、有效/错误、帧率（统计得到，非硬编码）、最后包时间、通信超时告警 |
| CONTROL | 目标输入 + SEND/STOP/RESET、4 个预设实验、RUN DEMO LOOP（Demo 模式有效） |
| 图表 | POSITION（目标/实际）、ERROR（目标−实际）、VELOCITY（滚动窗口） |
| EVENT LOG | 时间戳事件流（连接/目标/状态跳变/故障/超时） |

## 2. 浏览器要求

- 使用 **Chrome** 或 **Edge**（≥89），且必须运行在 **`localhost` 或 HTTPS** 下才能使用 Web Serial。
- 若浏览器不支持 Web Serial，页面会提示
  `Web Serial is not supported in this browser. Please use Chrome or Edge.`，Demo 模式不受影响。
- 建议 Windows 10/11 + 已装 CH340 驱动（板载 USB2 = CH340，PC 出现 COM 口）。

## 3. 本地启动

任选其一（推荐 A）：

```bash
# A. 只服务本页（web/ 为根目录）
cd web
python -m http.server 8000
# 浏览器打开 http://localhost:8000
```

```bash
# B. 在仓库根目录启动（地址带 /web/）
python -m http.server 8000
# 浏览器打开 http://localhost:8000/web/
```

> ⚠️ 直接双击 `index.html`（`file://`）Demo 模式可运行，但 **Web Serial 不会工作**（浏览器安全限制）。

## 4. Demo Mode（无 FPGA 演示）

网页默认进入 DEMO 模式并自动跑一次 **Exp1：0°→90°**。可用控件：

- 输入框输入目标（0~180）→ **SEND**；
- **STOP**：立即停住（回 READY/IDLE）；
- **RESET**：中止/清除目标（故障时作为 **ACK** 复位）；
- 4 个预设实验按钮：
  `Exp1 0→90 · Exp2 90→150 · Exp3 150→30 · Exp4 0→180`；
- **▶ RUN DEMO LOOP**：自动循环四个实验，每段到位后自动开始下一段。

Demo 的运动模型与 RTL 同构（非随机数）：
目标 → 参考轨迹限速（`trajectory_planner` VEL=150°/s）→ P 反馈指令
（`pid_controller` KP≈2，输出限幅 ±60°/s）→ 一阶电机（`virtual_motor`，TAU=100 ms）
→ 位置积分限位 0~180。速度栏标注 **MODEL (sim)**。

## 5. FPGA 连接（Live FPGA Mode）

1. FPGA 烧录 `top_system`，SW0 拨上运行；USB2（CH340）接 PC；
2. 页面点 **CONNECT FPGA**，浏览器弹出串口选择框；
3. 选择 **COM 口**（如 COM7），点连接；
4. 成功后：模式徽标变 **LIVE FPGA**、链路指示 **● CONNECTED**、显示端口与帧率；
5. 此时目标/位置/状态/曲线全部来自 FPGA 遥测。

断开：点 **DISCONNECT**，或直接拔线（页面自动检测并切回 DEMO，并记 EVENT LOG）。

## 6. COM 口选择

Web Serial 无法自动枚举指定端口，需要用户在弹窗中选择板上 CH340 对应 COM 口：

- 板载两个 USB：**USB1 = JTAG 下载**，**USB2 = CH340 串口**；
- 在设备管理器「端口 (COM 和 LPT)」中查看是 COM 几；
- 若弹窗为空：确认接线/USB2、CH340 驱动已装、端口未被 SSCOM/其他软件占用（占用会连接失败）。

## 7. UART 参数

固定为：

| 参数 | 值 |
|---|---|
| Baud | 115200 |
| Data | 8 |
| Parity | 无 |
| Stop | 1 |

## 8. 遥测协议（依据 RTL，非 README 猜测）

帧格式（`rtl/uart_telemetry.v`，每 `TELEM_MS = 100 ms` 一帧 ≈ **10 Hz**，经 `uart_tx.v` 115200 发出）：

```
[0]     0xAA            帧头
[1]     state           状态机编码  0..4（见下）
[2]     target          目标位置低 8 位（内部 10 位，0~180 < 256，无截断）
[3]     pos             实际位置低 8 位（同上）
[4]     chk             chk = 0xAA ^ state ^ target ^ pos
```

`state` 编码来自 `top_system.v` 中 `st8 = {5'd0, fstate}`，对应 `rtl/state_machine.v`：

| 值 | 状态 | 含义 |
|---|---|---|
| 0 | IDLE | 空闲 |
| 1 | READY | 已设目标未启动 |
| 2 | MOVE | 运动中 |
| 3 | HOLD | 到位保持 |
| 4 | FAULT | 故障锁定 |

> ⚠️ FPGA 遥测帧**不含速度/PDO/温度/电流**。因此 Live 模式速度要么不显示
> （首个帧前为 N/A），要么用连续位置差估算并标注 **EST (Δpos)**——页面**不会**伪造真实数据。
> Demo 模式速度来自仿真模型，标注 MODEL。

解析器（`TelemetryParser`，app.js）为滑动缓冲，正确处理**半帧 / 一帧 / 多帧 / 粘包 / 坏校验**，
坏帧跳过并计数；页面提供计数器（RX / VALID / ERROR）。可用控制台自测：

```js
window.__twin.runSelfTests()   // 返回 {ok, total, pass, failed}
```

## 9. 常见问题

**Q1 点 CONNECT FPGA 没反应 / 报 unsupported？**
需 Chrome/Edge + localhost/HTTPS。用 `python -m http.server` 打开，不要双击 HTML。

**Q2 连接后没有数据、LINK 显示 LINKING/TIMEOUT？**
先确认 FPGA 正在发遥测（SSCOM 能收到 `AA …`）；确认选对 COM、115200；
拔掉其他占用该串口的软件；SW0 拨上运行。

**Q3 机器人不动？**
Demo：确认点了 SEND/实验（故障时先 RESET）。Live：目标需在 **FPGA 键盘**输入
（KEY0-9 输目标，KEY11=GO）。FPGA 当前**没有 UART RX 命令协议**，所以 Live 模式
网页按钮已禁用为只读（见 §10 二期计划）。

**Q4 显示 TIMEOUT 是不是坏了？**
不是。2 s 没收到帧是**通信故障**（Communication Fault），与机器人 FAULT 区分。
页面把机器人 FAULT 单独用红色横幅表示；通信超时是黄色告警。

**Q5 速度怎么一会儿 EST 一会儿 N/A？**
Live 首两帧之间无两点可算，显示 N/A；有两帧后按 Δpos/Δt 估算并平滑，标注 EST。

**Q6 图表/内存会不会越来越大？**
不会。数据窗口固定（约最近 15 s / 上限 1500 点），旧点自动丢弃。

## 10. 故障排查（Debug）

- 浏览器控制台（F12）无 JS 报错即基本正常；`window.__twin` 暴露调试句柄：
  `parser`（解析器）、`demo`（仿真器）、`ctrl`（控制器）、`feedLive(bytes)`（喂字节测解析）。
- 无硬件快速自检（Live 管道，含故障）：见上文 §8 自测函数。
- 帧率显示为统计值（最近 3 s 有效帧数 ÷ 3），非固定 10 Hz。

---

### 二期方向（不影响当前一阶段）

1. **双向控制**：为 `top_system` 增加 UART RX 命令通道
   （设计命令帧 → ModelSim 仿真 → 板级验证），再解锁网页 CONTROL 面板的 Live 模式按钮；
2. ES8388 音频感知（方向估计）接入决策 → 轨迹 → 机器人，网页增加 AUDIO PERCEPTION 面板；
3. GitHub Pages 部署（Demo Mode 可直接展示，Live 仍需本机 localhost/HTTPS + Web Serial）。
