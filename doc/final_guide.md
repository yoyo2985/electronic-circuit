# 第 11–15 阶段自测与下载指南（09-07 已完成仿真）

> 以下模块均已 **ModelSim 仿真 PASS**。回来只需按表建工程/下板核对现象。
> 公共经验：rst_n=SW0(A9) 拨**上**=运行；数码管 = 0~180 位置；UART=115200 8N1。

## 模块清单与仿真结果

| 步 | 文件 | 现象核对 |
|---|---|---|
| 11 | `rtl/trajectory_planner.v` | ref 单调升/降到目标不超调(tb_trajectory_planner PASS) |
| 12 | `rtl/state_machine.v` | IDLE/READY/MOVE/HOLD/FAULT 转移(tb_state_machine PASS) |
| 13 | `rtl/fault_detector.v` | 堵转报故障、移动/停动清除(tb_fault_detector PASS) |
| 15 | `rtl/uart_telemetry.v` | 帧 [AA][st][tgt][pos][chk] 正确(tb_uart_telemetry PASS) |
| 14 | `rtl/top_system.v` | 键盘输入→轨迹→PID→电机收敛→强故障→CLR 复位(tb_top_system PASS) |

## 一键仿真（全部 TB，逐个 vsim 运行）

在 Git Bash 里（当前目录 sim/）：
```
for tb in tb_trajectory_planner tb_state_machine tb_fault_detector \
          tb_uart_telemetry tb_top_system; do
  vsim -c work.$tb -do "run -all; quit -f"
done
```
（`modelsim.do` 仅用于编译所有源文件+测试台；因 `quit -sim` 语义，单个 vsim 里跑完会退出，建议用上面的循环逐个跑。）

## 14 整机下板（推荐烧这个看全系统）

新建工程，源文件加 **12 个**（都来自 rtl/）：
`clock_enable.v, seven_seg.v, keypad_scan.v, target_input.v, state_machine.v,
virtual_motor.v, trajectory_planner.v, pid_controller.v, fault_detector.v,
uart_tx.v, uart_telemetry.v, top_system.v`
约束：`constr/top_system.adc`；顶层：**`top_system`**

### 板上操作
1. SW0 拨上运行；数码管显示位置(0~180)。
2. 按 KEY9、KEY0 → 目标 90（LED0=有目标亮）。
3. 按 KEY11(ENTER) → 启动，电机沿轨迹平滑转到 90 停稳：
   - LED1=运动中(亮)，到位后 LED2 亮。
4. 拨 SW2 到上 → 模拟堵转/碰撞 → **LED3(故障)亮**，电机停。
5. SW2 拨回下 → 按 KEY10(CLR) → 清除故障回待命。
6. UART(COM7, 115200)：SSCOM 应收到滚动帧（`AA 02 5A xx …`），每 ~100ms 一帧。

## 16 PC 端“数字孪生”

接好 CH340 后：
```
python tools/pc_twin.py COM7            # 控制台看 state/target/pos
python tools/pc_twin.py COM7 --plot     # 实时位置曲线
```
（依赖 pyserial；画图需 matplotlib）

## 可选加分 17/18
- 17 DAC（R-2R 复用 LED 脚）未实现，如需再加。
- 18 ES8388 依赖音频外设，第一阶段明确不使用。
