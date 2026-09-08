# B5 Feature_engine → vtmpl 声纹认证闭环 — Implementation Specification（v1，待执行）

> 本轮只审计与定规格，未写 RTL。B4（feature_engine，N64/M20/K13，三组逐位 PASS）为不可破坏基线。

## 1. 代码审计结论（读真实代码）

### 1.1 vtmpl（C2-lite）真实接口
| 项 | 现状 |
|---|---|
| 参数 | `DIM=4`（默认）、`TH=500`（默认） |
| 端口 | clk, rst_n, `in_valid`, `in_v[15:0] signed`, `out_valid`, `out_dist[31:0]`, `out_match` |
| ROM | `initial $readmemh("data/vtmpl.mem", tpl)` — DIM 个 **signed 16-bit**（hex4 两补） |
| 行为 | 每来 DIM 个 `in_v`（连续分组）后：`dist=Σ|in_v−tpl|`（内部 40bit 累加）→ `out_dist=acc[31:0]`，`out_match=(dist<=TH)`；无 enable/start/frame/done——靠**按 DIM 连续喂 + out_valid 分组** |
| 无 enable | 由外部 wrapper 控喂即可（见 §5） |

### 1.2 B4 feature_engine 输出
`feature_valid`（每维 1 拍）、`feature_index[3:0]`=0..12、`feature_data signed[15:0]`、`frame_done`、`busy`、输入 `enable`/`frame_start`/`pcm_valid`/`pcm_data[23:0]`。
B4 内 DCT 已 `>>>12`；`feature_data = dct_c >> COEF_Q`（当前 COEF_Q=0）截成 16-bit。

## 2. MFCC 32→16 定标分析
- 实测（B4 三组）：sine∈[−3035,2242]，rand∈[−6340,8479]，零=0 —— 当前样本都在 int16 内。
- 理论界：正交 DCT-II 输出系数 |c_k| ≤ √Σx²（log-mel int16），极端可能越界。
- 结论：**不允许裸 `[15:0]` 截断**；B5.2 加 `mfcc_quant`：
  `mfcc16 = sat16( dct_c >>> QS )`，`QS`(0..7) 与 template 构建用同一 QS（同一 DCT 值域），`QS` 由 Python 对 owner 数据统计最大值选定，模板与该量化一致 → L1 尺度不漂移。
  （feature_engine 已留 `COEF_Q` 参数；B5 把定标独立到 quantizer，不改 B4 已 PASS 逻辑。）

## 3. distance 位宽
DIM=13、|Δ|max=65535 → **Σmax = 13×65535 = 851955**（<2^20）。
vtmpl 内部 40bit 累加、`out_dist[31:0]` —— **无溢出**；不用扩宽，只需把 DIM 从默认 4 改为 **13**（参数化，算法零改动）。

## 4. Template ROM 格式（与 vtmpl/engine 对齐）
`rtl/data/owner_template.mem`（约定目录可后续并入 constr/工程）：
- 13 行，每行一个 **signed 16-bit（两补 hex4，小端无关：逐维顺序）**
- 维序与 B4 MFCC 输出一致：k=0..12
- 生成自 Python（round→saturate→int16），不做 hardcode

## 5. B5 帧协议与集成结构
```
feature_engine
  feature_valid/index/data  (13/帧, 顺序 0..12)
        ▼
 speaker_verify (wrapper)
   收集 13 维 → 喂 vtmpl(DIM13) 每帧 13 维 → out_valid/dist/match
        ▼
 frame_match
```
- wrapper 必须保证**按帧喂**：收到 engine `feature_valid` 逐维存入 reg[12:0][15:0]，`feature_index`=12 且下一拍 `frame_done` 后，把 13 维按序以 `vtmpl.in_valid` 送 13 拍；vtmpl 在第 13 拍给出该帧 `out_valid/dist/match`。
- 输出：`owner_valid`（第一版=单帧 match，按 §utterance 升级为片段多数投票后再给 decision_fsm）。
- `TH` 不写死进 RTL：顶层 parameter，值来自 §8 数据阈值分析。

## 6. 本阶段 RTL 模块
- B5.2 `mfcc_quant`（32→16，QS+饱和，Python 验证范围）
- B5.3 `speaker_verify`（feature_engine→vtmpl 帧对齐 wrapper）
- B5.7（可选阶段）`utter_vote`（片段内多帧 match 多数投票）

## 7. Python speaker pipeline（全部离线；运行时只在 FPGA）
目录 `data/speaker/{owner,impostor_A,impostor_B,impostor_C}`（先建骨架；WAV 后补）。
工具（都复用 B4 Golden `py/frontend.py` / 镜像链，禁止第二套 MFCC）：
- `tools/speaker_preprocess.py`：WAV→读→校验 fs/ch→mono→重采样48k→24bit，再走 B4 Golden
- `tools/build_speaker_template.py`：owner 多条录音→逐帧 MFCC（含能量门 VAD 去静音，注明“离线注册临时 VAD”）→ **mean(MFCC)**→round/sat/int16→`owner_template.mem`
- `tools/evaluate_speaker_verification.py`：owner test vs impostor，输出 accept/reject、FAR/FRR、distance 统计、多阈值表、推荐 threshold（低 FAR 工作点；数据足则 EER）
- 训练/测试集**分开**，不用同录音做模板又做测试

## 8. 阈值策略
threshold 必须来自数据（owner-owner vs owner-impostor 距离分布），报告 FAR/FRR/accuracy，选取**偏低 FAR** 工作点（主人专属控制宁可误拒勿误放）。

## 9. B5 测试（RTL, 向量由 Python 生成）
1 template+feature 全同 → dist=0 match=1
2 template+小差 → match=1
3 template+大差 → match=0
4 极值 32767/−32768 → distance 不溢出
5 13 维定种子随机 → RTL vs Python 逐位一致（dist & match）
6 （接入后）feature_engine 全链→vtmpl 端到端 vs Python 帧对齐

## 10. 资源/时序（估算；综合后补报表）
feature_engine+vtmpl 全链为顺序/复用乘法器，预计 LUT/FF 中等、BRAM 存 ROM/表；真实 LUT/FF/BRAM/DSP/Fmax/timing 待 TD 综合统计（离线下板环境未做，列为待办）。帧周期 1.33ms ≫ 处理周期，实时可行性同 B4。

## 11. 不要做（B5 红线）
修 ES8388 MIC / D2 连续角 / 神经网络声纹 / ESP32·STM32 / 改 B4 FFT·Mel·DCT / Python 当实时计算器 / 拍脑袋 threshold / 同批 WAV 即模板又测试 / 因无 WAV 而停摆 / 堆无必要模块。

## 12. 执行顺序
B5.1 审计（本规格）→ B5.2 mfcc_quant（Python 定 QS+范围）→ B5.3 speaker_verify（feature→vtmpl 帧对齐，合成模板跑 §9）→ B5.4 owner_template.mem（合成模板先验证）→ B5.5/6 真 WAV 到位后模板+evaluation → B5.7 片段多数投票。每阶段：git status→add→commit。
