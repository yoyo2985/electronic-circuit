# Speaker Verification 固件一致性审计（2026-09-10，只读）

范围：`top_voice_robot`（TD_EG4_voice_robot 综合顶层）的 Who 链
`v2_frame_ctrl → feature_engine → speaker_verify(vtmpl) → utter_vote → voice_dbg_rpt`。
结论先行：**固件一致（结论 A）**——bit 内是 TH=2500 + 新 owner 模板 + 当前 speaker_verify/voice_dbg_rpt；
Python 与 RTL 距离**同尺度、无任何缩放**。板上现象由「定标统计量（段均值）≠ 运行统计量（单帧）」造成，见 §8。

---

## 1. speaker_verify.v 全参数与内部计算（当前综合文件 rtl/speaker_verify.v）

- **SPK_TH 定义/数值**：定义在顶层 [rtl/top_voice_robot.v:38](rtl/top_voice_robot.v) `parameter SPK_TH = 2500`。
  `speaker_verify` 模块自身默认 `TH = 5000`（[rtl/speaker_verify.v:9](rtl/speaker_verify.v)），但**唯一进入综合的实例化**
  [rtl/top_voice_robot.v:332](rtl/top_voice_robot.v) `speaker_verify #(.TH(SPK_TH)) u_sv` 显式覆盖为 2500。
- **位宽**：TH 为参数，vtmpl 内与 40-bit `acc` 比较（`out_match <= (acc <= TH)`），比较在 40-bit 下完成，TH=2500 无截断。
- **距离公式（vtmpl，[rtl/vtmpl.v:38-43](rtl/vtmpl.v)）**：
  ```
  d = $signed(in_v) - t_cur;  if (d < 0) d = -d;   // 每维
  acc = acc + d;                                     // 13 维累加
  out_dist = acc[31:0];  out_match = (acc <= TH);
  ```
- **差值位宽**：`in_v` 与 `t_cur` 均为 `signed [15:0]`。差值 `d` 声明为 `signed [39:0]`（reg），计算用 40-bit，
  单维最大 |16-bit 差| = 65535，无溢出。
- **abs 实现**：`if (d < 0) d = -d;` 在 40-bit 有符号下取模；输入两端最大差 65535 < 2^39，无 ±32768 陷阱。
- **累加位宽**：`acc` 为 `signed [39:0]`。理论最大 L1 = 13 × 65535 = 851955 < 2^20，**远小于 2^39，无饱和/无溢出**。
- **shift / truncation / rounding / signed-unsigned 转换**：**都没有**。逐维 `d`、累加 `acc`、输出 `out_dist[31:0]`
  全是同一个量。唯一位移出现在上游 feature_engine（`dct_c >>> COEF_Q`，算术右移，采集与运行共用同一 fe_data，两边尺度相同）。
- **sv_dist 尺度**：即 vtmpl 的 `out_dist = L1(单帧13维 MFCC int16, 模板 int16)`。与 Python 段均值 L1 同单位、同尺度。
- **fr_match 判定**：`out_match = (acc <= TH)`，即 **fr_match ⟺ sv_dist ≤ 2500**（小于等于，非严格小于）。审计 tb 边界验证：2500→match、2501→不match。
- **owner_valid 位置**：**不在 speaker_verify 内**。speaker_verify 只出单帧 `frame_match`；段级 `owner_valid` 在
  [rtl/utter_vote.v](rtl/utter_vote.v) 内产生（VAD 段内累计匹配帧，`acc ≥ MIN_MATCH(5)` 即粘性置 1，段末复位）。

## 2. debug score 来源（rtl/voice_dbg_rpt.v + 顶层布线）

- `voice_dbg_rpt` 的 `score` 输入由顶层接 **`sv_dist[15:8]`**（[rtl/top_voice_robot.v:405](rtl/top_voice_robot.v)），确认无误。
  `sv_dist` 是 speaker_verify 锁存的 `frame_dist`（最后一帧的 vtmpl out_dist）。
- [AB] 帧字节布局（[rtl/voice_dbg_rpt.v:4](rtl/voice_dbg_rpt.v)）：`[0]AB [1]vad [2]mfcc_any [3]{6'b0,fr_any,owner} [4]cmd [5]act [6]score [7]chk`。
  - `[3] bit0 = owner` = **utter_vote 的 uv_owner**（段级粘性）
  - `[3] bit1 = fr_any`（自上次上报以来**任一帧**匹配过的锁存脉冲，不是瞬时 fr_match）
- **score↔sv_dist 换算**：
  - sv_dist=1532 → score=1532>>8=**0x05**
  - sv_dist=2500 → score=2500>>8=**0x09**
  - score=0x0D → sv_dist ∈ [0x0D00, 0x0DFF]=**[3328, 3583]**（最小 3328）
- 实测 score 0x0D–0x3A ⇒ 单帧 sv_dist ≈ **3328–15103**，全部（除个别帧）> 2500 → 解释了「fr 偶尔、owner 不稳定」。

## 3. threshold 全工程审计

| 位置 | 值 | 是否生效 |
|---|---|---|
| rtl/top_voice_robot.v:38 `parameter SPK_TH = 2500` | 2500 | ✅ 综合顶层默认值 |
| rtl/speaker_verify.v:9 `parameter TH = 5000` | 5000 | ⚠️ 仅模块默认，被顶层 `#(.TH(SPK_TH))` 覆盖，综合用 2500 |
| rtl/top_voice_system.v:64 `speaker_verify u_sv`（**无** TH 覆盖） | 5000 | ⛔ **不参与构建**（不在任何 .prj/.al/.do；综合顶层是 top_voice_robot） |
| 其它 `5000` 命中 | 全为 `MS_DIV=50000` | 无关 |

无 `localparam/`define/`defparam` 覆盖；顶层 tcl `elaborate -top {top_voice_robot}` 不传参数 ⇒ **综合实际值 = 2500**。

## 4. owner 模板审计

- 模板**不是文件载入**：TD 不支持 `$readmemh`，模板以 **208-bit 参数常量内嵌**于
  [rtl/speaker_verify.v:10](rtl/speaker_verify.v) `TPLV = 208'h001c0051...fb500bc9`（本次综合值）。
- `data/speaker/owner_template.mem`（工作区，2026-09-10 重建，78B）与 TPLV 逐维一致（上轮 mem↔字面量校验通过）。
- 综合工程不引用 .mem——`speaker_verify.v` 的 TPLV 参数即是「最终综合使用的 owner 模板」。**无旧目录/复制文件/缓存问题**：
  - 全库仅一份 `rtl/speaker_verify.v`（find 确认，无副本）。
  - .prj 引用 `../../../rtl/speaker_verify.v`（实时源文件，不是缓存）。
  - `.al`（Sep 10 00:35 旧归档）不参与 `open_project *.prj` 的 headless 综合，仅工程管理用。
- 佐证：审计 tb 喂 TPLV 自身 → dist=0，即 RTL 内嵌值确为新 owner 模板。

## 5. bitstream 构建链

```
rtl/speaker_verify.v(+TPLV) → syn_1 (11:18 gate.db) → phy_1 (11:21 .bit) → best_result/TD_EG4_voice_robot.bit
RTL 改动时间 11:01-11:02 ＜ gate.db 11:18 ＜ bit 11:21 ✓（本次改动全部先于构建）
```
- 综合顶层 tcl 用默认参数（SPK_TH=2500）；bit 由当前源综合，hash `e107d868…`（旧 `02a962…`）。
  自旧 bit 以来 RTL 仅 4 处变化：TPLV、TPL0-3、SPK_TH→2500，故新 bit 必然包含三者。
- **未重新生成 bitstream**（本次只读）。

## 6. 尺度对应表（Python ↔ RTL ↔ score ↔ 判定）

| 项目 | 数值 | 说明 |
|---|---|---|
| Python owner max（段均值） | 1532 | 属主 7 段均值 vs 组均值模板，L1 最大 |
| Python impostor min（段均值） | 4487 | 陌生人"前进"段均值 vs owner 模板，L1 最小 |
| RTL owner 距离 | 逐帧 **3328–15103**（实测 score 0x0D–0x3A） | 同尺度；单帧方差远大于段均值 |
| RTL impostor 距离 | ≥4487（同尺度） | 段均值口径可直接外推 |
| SPK_TH | **2500** | 综合顶层参数，作用于单帧 |
| debug score | **score = sv_dist[15:8]**（0x05↔1532，0x09↔2500，0x0D↔≥3328） | 顶层硬连线 |
| fr_match 判定 | **fr_match ⟺ sv_dist ≤ 2500** | vtmpl `acc<=TH`，≤ 非 <，2500 本身通过 |

**数学缩放关系：二者是同一个量，无 ×2、无 >>N。**
RTL `out_dist` 与 Python `L1(帧向量,模板)` 逐位相等——审计 tb 以 0/2499/2500/2501/4487/1532 六个已知点全部逐位匹配。
（采集端 `voice_cap_rpt` 直接累加 `fe_data`（int16），feature_engine 的 `>>>COEF_Q` 缩放为采集与运行共用，尺度自洽。）

## 7. fr_match ⟺ sv_dist ≤ SPK_TH：直接从 RTL 证明

[rtl/vtmpl.v:43](rtl/vtmpl.v)：`out_match <= (acc <= TH) ? 1'b1 : 1'b0`；`acc` 即本帧 13 维 L1；
speaker_verify 将 vtmpl 的 TH 端口接顶层 SPK_TH。链路无任何二次比较/阈值。边界实测：
dist=2499→1、dist=2500→1、dist=2501→0。**等价成立（≤，含等号）。**

## 8. 板上现象根因（不是固件不一致）

Test A 观察（owner=0/偶尔 1，score 0x0D–0x3A）与当前固件**完全自洽**，机制是：
- 离线定标统计的是**段均值**距离（max_own=1532）——那是 ~1000 帧平均后与模板的 L1；
- 硬件把 TH=2500 施加在**单帧**距离上。单帧 MFCC 在"机器人 你好"的音素/停连/响度起伏下偏离均值模板很远
  （安静帧全体维→0，距模板 L1≈Σ|T|=**7279** 即 score 0x1C；响音帧更高，观测 0x3A≈15103）。
- 故 TH=2500 对段均值宽裕，对单帧却拒绝绝大多数 → fr_match 偶发（<2500 的帧少），
  utter_vote 需段内累计 5 个匹配帧 → owner 难以稳定为 1。这正复现 Test A。

**这不是「固件烧错/模板没更新/尺度对不上」，而是「定标统计量（段均值）≠ 运行统计量（单帧）」的方法学问题。**
（另注：5000→2500 换入后，陌生人被更稳地拒于闸外，但同向压低了属主单帧通过率——单帧匹配率本就是这个架构的弱环，
utter_vote 段级累计就是为它设计的。）

## 9. 附带发现（非本次问题根因）

- `rtl/top_voice_system.v` 内 `speaker_verify u_sv` 未覆盖 TH（=5000）且不进入任何构建——**死代码/误导源**，
  建议日后清理（本次不动）。
- score 是「最近一帧」距离的 200ms 采样，不是段均值；解读板上 score 时勿与 Python 段均值直接对比。

## 10. 审计方法（可复现）

- 静态：全工程 grep SPK_TH/5000/2500；.prj/.al 引用链；构建时间戳比对。
- 动态：[sim/tb_spk_audit.v](sim/tb_spk_audit.v)（只读，不改 RTL/不重建固件），用综合同源码 + 内嵌 TPLV + TH=2500，
  6 个已知距离点全过（12/12 PASS）。

---
## 追加(2026-09-10 闭环优先): SPK_TH 2500 → 4000
审计结论维持 A 类。为优先保证 TEST 1(属主过闸)稳定、进入闭环演示，SPK_TH 已按工程基线改为 **4000**
（owner 单帧低端实测 3328、stranger 段均值 min 4487，取其间）。此值优于 2500 处：
owner 单帧通过率显著提高；仍低于最近陌生人段均值。局限如实记录：单帧分布重叠 → TEST 3 可能漏放；
真正分净需段级决策（本次按约束不实施）。固件：best_result/TD_EG4_voice_robot.bit `7516c10b…`，回归 PASS。
