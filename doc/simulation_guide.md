# ModelSim 仿真指南（初学者）

> 流程：写模块 → 写 Testbench → ModelSim 看波形 → 通过 → 才进 TD 综合。本轮 3 个 TB 都要先过。

## A. 建工程

1. ModelSim → **File → New → Project** → 名 `robot_sim`，路径选 `sim/`。
2. **Add Existing File**：加入
   - `rtl/clock_enable.v` `rtl/led_ctrl.v` `rtl/seven_seg.v`
   - `sim/tb_clock_enable.v` `sim/tb_led_ctrl.v` `sim/tb_seven_seg.v`
3. 编译时所有 RTL + TB 要一起（TB 依赖 RTL）。

## B. 编译

- 菜单 **Compile → Compile All**，或右键文件 Compile。
- 看 **Transcript** 窗口：有 `Error` 必须修；`Warning` 先记下。
- 常见错误：`$clog2` 不识别 → 用 `vlog -sv` 编译（SystemVerilog 模式）。

## C. 仿真（以 tb_clock_enable 为例）

1. **Simulate → Start Simulation** → 展开 `work` → 选 `tb_clock_enable` → OK。
2. **Objects** 窗口（默认在右侧）选中 `clk`、`rst_n`、`tick`、`cyc`、`pulses`
   → 右键 **Add Wave**（或工具栏 Add → To Wave → Signals in Region）。
3. 工具栏 **Run -All**（绿色长跑按钮）。
4. 看 `tick` 是否每 50 个 `clk` 出现 1 个尖峰。
5. 重跑：**Simulate → Restart**（保留波形信号，清数据）。

## D. 切换到其它 TB

- 先 **Restart**，再 **Simulate → Start Simulation** 选 `tb_led_ctrl` / `tb_seven_seg`。
- 重新 Add Wave 即可。

## E. 判断通过

| TB | 通过标志 |
|---|---|
| tb_clock_enable | Transcript 出 `PASS: 收到 5 个 tick`；波形 `tick` 周期 = MS_DIV |
| tb_led_ctrl | `LED0` 周期翻转，`LED7..1` 单 bit 左移 |
| tb_seven_seg | `dig_cs` 轮流 1110/1101/1011/0111，`seg` 与字形表一致 |

## F. 批量跑（可选）

命令行进入 `sim/`：

```bash
vsim -do modelsim.do
```

脚本会编译并依次跑 3 个 TB，Transcript 里看结果。

## G. 免费替代（如果没装 ModelSim）

Icarus Verilog + GTKWave：

```bash
iverilog -o vp -I ../rtl ../rtl/*.v *.v
vvp vp
# 看 VCD 用 gtkwave（需要 TB 里加 $dumpfile/$dumpvars，可后续补）
```

本课程以 ModelSim 为准，Icarus 仅作备选。
