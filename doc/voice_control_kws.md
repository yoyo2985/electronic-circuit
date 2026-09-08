# Voice Control KWS（Who + What）并行架构说明

> 增量新增，不改 `speaker_verify.v / utter_vote.v / feature_engine.v / decision_fsm.v / motion_plan.v`。
> “Who”=声纹链(已有)，"What"=命令链(新)：`cmd_matcher → cmd_vote`，两者共享 `feature_engine` 的 13-D MFCC。

## 1. 数据流
```
feature_engine(feature_valid/index/data, 13/帧)
   ├──▶ speaker_verify ──▶ utter_vote ──▶ owner_valid      (Who)
   └──▶ cmd_matcher (4×vtmpl L1) ──▶ cmd_id ──▶ cmd_vote ──▶ cmd_id_out (What)
   decision:  (owner_valid && cmd_vote.decision_valid) → 执行 action(cmd_id_out) 否则 IDLE
```

## 2. 决策真值表（owner_valid + cmd_valid→action）
| owner_valid | cmd_valid/decision_valid | cmd_id_out | 动作 |
|---|---|---|---|
| 0 | x | x | IDLE（不执行） |
| 1 | 0(窗口未满) | x | 保持/等待 |
| 1 | 1 | 0=stop | STOP |
| 1 | 1 | 1=left | 左转 |
| 1 | 1 | 2=right | 右转 |
| 1 | 1 | 3=forward | 前进 |

动作码沿用 `motion_plan`：0 IDLE/1 REJECT/2 FORWARD/3 LEFT/4 RIGHT；KWS 命令 0..3 映射到该动作（命令索引即动作，另把 cmd_id=0 映射 STOP(0)，避免与 REJECT 冲突可在封装层处理）。

## 3. 顶层例化片段（示意，添加到集成 top；勿改现有声纹例化）
```verilog
// ---- What 链（新增并行）----
wire            sv_owner, uv_owner, uv_dec;
wire [1:0]      cmdid;
wire            cmdv, cmddec;
wire [31:0]     cmd_dmin;

speaker_verify u_sv ( /* 原样保留 */ ... .owner_valid(uv_owner) );
utter_vote u_uv ( .clk,.rst_n, .frame_valid(...), .frame_match(uv_owner),
                  .decision_valid(uv_dec), .owner_valid(owner_out), .frames_seen() );

cmd_matcher #(.NUM(4)) u_cmd (
    .clk,.rst_n, .mfcc_valid(feature_valid), .mfcc_data(feature_data),
    .cmd_valid(cmdv), .cmd_id(cmdid), .cmd_dist_min(cmd_dmin));
cmd_vote #(.VOTE_N(8),.NUM(4)) u_cmdv (
    .clk,.rst_n, .cmd_valid(cmdv), .cmd_id(cmdid),
    .decision_valid(cmddec), .cmd_id_out(cmd_id_out), .frames_seen());

// 决策 = 主人 && 命令有效 → motion_plan(action=cmd_id_out→映射)
// 建议由新封装模块 voice_action 输出 motion_plan.action，避免改 decision_fsm。
```

## 4. 复现/验证
- 模板生成：`python tools/gen_command_templates.py`（需 `sounds/commands/<name>/*.(wav|m4a)`）；
  无真实命令时仿真用合成模板（`python py/cmd_golden.py` 生成 `data/commands/cmd_0..3.mem` 与 `data/cmd_*` 向量）。
- RTL 单测：`tb_cmd_matcher`(每帧 id 与 python 一致)、`tb_cmd_vote`(窗口众数与 python 一致)。

## 5. 红线遵守
未修改 speaker/utter/feature_engine/vtmpl 逻辑；KWS 全部为新增文件；command 模板在 `data/commands/`（git 如需可再排除）。
