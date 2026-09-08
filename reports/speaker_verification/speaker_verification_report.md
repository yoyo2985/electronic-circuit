# Speaker Verification Baseline 报告（B5.4–B5.6，真实 m4a）

日期：2026-09-08。方案：**MFCC(13) + L1 + mean-template** 轻量级 baseline（非深度 speaker embedding）。
用途：仅用于建立可复现 baseline；**当前结果不满足部署**，是如实记录，不做美化。

## 1. 数据集
- owner_sound 15 条、stranger1 14 条、stranger2 10 条，全部 `.m4a`(AAC)。
- 采样率 48000、2ch、fltp、时长 1.5–24 s；无空文件/无整段静音。
- 预处理：PyAV 解码→48k→取 **L 声道**（R 保留，未用）；16-bit int16。
- 注：录音由手机录制，主人与陌生人录制**内容高度相似（多半同为简短命令）**。

## 2. 前端参数（与 FPGA feature_engine/B4 一致）
frame=64(hop=64, 1.33ms)、FFT 64、power bins 33、mel 20、MFCC 13、PS=22；
int16→int24(×2^8) 后走 B4 整数镜像；输出 13×int16。
能量门（离线临时 VAD）：帧 RMS≥max(60, 0.08·本文件峰值RMS)；活动帧合计 **259,581**。

## 3. 模板
owner 15 条 → sorted 前 70%(11 条) 注册、后 30%(4 条) 测试（同文件不跨集）。
模板 = 注册活动帧 13 维均值 → round/int16 → `data/speaker/owner_template.mem`（13 行 hex4）。
注册帧 56,014。

## 4. 帧级评估
- owner_test 帧 19,759；impostor(两陌生人)帧 183,808。
- owner dist mean 3369 ±2069 (p95 7527)；impostor mean 3385 ±2033 (min 597)。
- **两分布几乎完全重叠**；帧级不可分（EER≈50%，FAR0 需 TH≤597 但 owner 全拒）。

## 5. 录音级评估（每段均值特征，去 c0 后 L1）
- owner 4 段：1002/1505/1610/2702；impostor 24 段：min 351、多个 <1000。
- 仍重叠 → **录音级也不可分**（且存在陌生人距离 < 主人，方向相反）。

## 6. 结论与原因分析（诚实）
1. 13 维短时 MFCC+L1 对该数据/这种内容相似录制**区分力不足**；
2. 内容高度一致（都喊类似命令）→ 更像“内容相似”，对说话人辨识不利；
3. 短 1.33ms 帧噪声大、模板仅均值；缺声道/韵律长期特征；
4. 未见“同一句话不同人 + 不同话同一人”受控对照，无法排除内容识别混入。

**因此：不推荐以任何固定 TH 上线。** 当前 `TH=5000` 仅是占位。应继续 B5.7 投票并改进前端（更长窗/整句均值、更多录音、受控内容录制、可能去 c0/降能量项），再做 FAR/FRR。

## 7. 输出文件
- `reports/speaker_verification/threshold_results.csv`（帧级 sweep）
- `reports/speaker_verification/evaluate_report.txt`、`dataset_audit.txt`
- `data/speaker/owner_template.mem`、`split.json`

## 8. RTL/Python 一致性
feature_engine==scalar==vector 镜像逐位一致（audio_golden 自检 max diff = 0），模板文件格式与 vtmpl(TPL=`data/speaker/owner_template.mem`) 对齐。阈值语义 = L1(int16) 与 vtmpl 一致。
