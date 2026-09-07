# 项目架构

## 总体（真实 FPGA + 虚拟对象 + PC 数字孪生）

```text
EG4S20 FPGA
  Input(键盘/拨码) → State Estimator → Decision → Trajectory → PID
       → Virtual Motor → Virtual Encoder → Fault Detection
  侧路：Display(数码管/LED) / 蜂鸣器 / DAC / UART → PC 数字孪生
```

感知接口与控制算法解耦：将来 Sensor Input 可换成 虚拟传感器 / ADC / ES8388 I2S，后端 Decision/Trajectory/PID/Virtual Robot 不变。

## 模块清单（rtl/）

| 文件 | 职责 | 阶段 |
|---|---|---|
| clock_enable.v | 50 MHz → tick_1ms | 01-02 ✅ 第一轮 |
| led_ctrl.v | LED 心跳 / 跑灯 | 01 ✅ 第一轮 |
| seven_seg.v | 4 位数码管动态扫描 | 03 ✅ 第一轮 |
| switch_input.v | 拨码采样 | 04 |
| keypad_scan.v | 4×4 矩阵扫描 + 消抖 | 05 |
| uart_tx.v / uart_rx.v | 串口收发 | 06-07 |
| target_input.v | 目标角度输入 + 范围检查 | 08 |
| virtual_motor.v | 一阶离散虚拟电机 | 09 |
| pid_controller.v | 定点 PID + 限幅 | 10 |
| trajectory_planner.v | 限速 / 梯形轨迹 | 11 |
| state_machine.v | IDLE/READY/MOVE/HOLD/FAULT | 12 |
| fault_detector.v | 负载 / 碰撞检测 | 13 |
| top.v | 整合 | 14 |
| uart_protocol.v | 遥测帧 | 15 |
| dac_output.v | PID → DAC（加分） | 17 |

## 开发顺序（不得跳步）

01 LED → 02 Clock Enable → 03 Seven Segment → 04 Switch → 05 Keypad →
06 UART TX → 07 UART RX → 08 Target Input → 09 Virtual Motor → 10 PID →
11 Trajectory → 12 FSM → 13 Fault → 14 Top → 15 Telemetry → 16 PC Twin →
17 DAC → (可选) 18 ES8388

## 第一轮交付（本轮）

- 项目骨架：rtl/ sim/ constr/ doc/
- `clock_enable.v` / `led_ctrl.v` / `seven_seg.v`
- 对应 3 个 testbench
- 设计规范 + 接口说明 + ModelSim 指南 + 引脚参考表

## 下一步（仿真通过后）

`top_blink`（clock_enable + led_ctrl）+ 约束 + 下板看 LED；再进入 keypad / uart。
