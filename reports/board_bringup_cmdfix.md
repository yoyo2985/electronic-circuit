# 板上 cmd_id 恒 0 根因：cmd_matcher 模板参数字面量断层（已修）

日期：2026-09-09 → 2026-09-10。Debug bitstream（0xAB 语音帧）上板，两次真实 UART 抓包后定位。

---

## 1. 板上证据（SSCOM [AB] 帧，115200）

- 23:58 抓包（主人说话，未念命令）：VAD=1 / MFCC=1 正常，score 0x15–0x3E（6k–19k），owner 投票恒 0。
- 00:02 抓包（主人念命令词）：**cmd_id 恒 0**，fr_any 仅 2 帧，owner 投票 0。

前级链（ES8388→VAD→MFCC→[AB] 帧 + 校验和）板级工作正常；问题在后两级 Who/What。

## 2. 根因（WHAT 已定位为 RTL 缺陷，非通道失配）

`rtl/cmd_matcher.v` 原把 4 个命令模板写成**字符串文件路径**参数：

```verilog
parameter TPL0 = "../../data/commands/cmd_0.mem",   // 字符串!
```

传给 `vtmpl` 的 `TPLV`（`parameter [(DIM*16)-1:0] TPLV` 整数字面量参数）。综合后板上模板 =
**路径字符串的 ASCII 字节**，4 个路径只差一个字符 → 4 条 L1 距离几乎相等 → argmin 恒取 d0
→ **cmd_id 恒 0**。`speaker_verify.v` 用的是正确内嵌字面量，所以 WHO 有真实距离读数。

**此前“WHAT 根因是通道失配”的判断是错的，特此更正。** 通道失配只解释 WHO（6k–19k 距离）；
cmd_id=0 由这个模板字面量断层解释，与通道无关。

## 3. 修复（不重造轮子：沿 speaker_verify.v 已验证口径）

- `rtl/cmd_matcher.v`：TPL0–3 改为内嵌 208-bit 字面量，取自 **真实当前模板**
  `data/commands/cmd_{stop,left,right,forward}.mem`（`voice_replay_eval.py` 重新生成的那套；
  `cmd_0..3.mem` 为旧命名、已无生成器引用，判定为陈旧数据）。映射：
  `0=stop 1=left 2=right 3=forward`（与 `decision_fsm` 的 i_cmd_id 解码一致）。
- `rtl/top_voice_robot.v`：删除未用的字符串参数 SPK_TPL/CMD_TPL0–3（从未被实例化覆盖）；
  修正 §312 已过时注释。
- `rtl/top_voice_system.v` / `sim/tb_voice_control.v`：同一缺陷模式，去掉字符串路径覆盖，
  改走 cmd_matcher 默认（值一致，行为不变）。

## 4. 验证

- 新 tb `sim/tb_cmd_lit.v`（+`run_cmd_lit.do`）：对 4 个模板逐个喂原样 13 维向量 →
  **dist=0、argmin==自身索引，4/4 PASS**（证明字面量与 .mem 逐维一致、编码方向正确）。
- 回归：`tb_top_voice_robot`（[AA] 运动链）PASS；`tb_voice_dbg`（[AB] 帧 16 项）PASS。
- TD 综合：`voice_dbg_rpt.v` 曾被 GUI 保存工程时从 syn_1/.prj 与 .al **丢项**（black box 错），
  已补回 CompileOrder=40。

## 5. 待办 / 提醒

- 重新综合 → P&R → bitgen → 用户烧录复测命令词（看 [AB] 帧 cmd_id 是否随命令变化）。
- WHO 仍须板上重采：CAP_UART=1 采集主人 + 4 命令的真值 MFCC → 重建模板 + 数据驱动定 SPK_TH。
- ⚠️ 用户若再在 TD GUI 打开工程，会以 GUI 工程状态覆写 .prj/.al，可能再次丢 voice_dbg_rpt
  条目 → 烧录前若报 black box 需手工补回。
