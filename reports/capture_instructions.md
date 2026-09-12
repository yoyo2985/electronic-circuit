# 板上真值采集 (CAP_UART=1) 操作说明

配合 `best_result/TD_EG4_voice_robot_cap.bit` 使用。该固件的串口 TX **只发 M-line**
(每段语音一条, 114 字节: `M` + 帧数 + 13 维 int32 和 + 换行), 不发 [AA]/[AB]。

## 1. 烧录 + 接线
- 烧 `TD_EG4_voice_robot_cap.bit`, 上电。听蜂鸣器完成初始化三音确认 ES8388 OK。
- 串口 115200-8-N-1 连 PC (SSCOM 或任意终端), **打开时间戳**。

## 2. 说话规矩(重要)
- 每**一个词/短语**之间停 **0.5~1 秒** —— VAD 靠停顿分段, 一句话=一条 M-line。
- 不要说成连读, 否则两个字混进同一段, 均值模板变成混合。
- 环境尽量安静, 距麦 ~30cm。

## 3. 采集清单(按顺序说, 各说 N 遍)
| 顺序 | 内容 | 遍数 |
|------|------|------|
| 1 | 属主短语(之前注册的 owner 口令, 如"小巴小巴") | 3~5 |
| 2 | 停 | 3 |
| 3 | 左转 | 3 |
| 4 | 右转 | 3 |
| 5 | 前进 | 3 |
| 6 | **陌生人/冒充者**: 换一个人说上面任一命令(如"前进") | 3 |

第 6 组可有可无但强烈建议 —— 只有冒充者数据才能诚实确定 SPK_TH(见下)。

## 4. 保存日志
SSCOM 里把整个采集过程另存为文本文件, 如 `capture_20260910.txt`。

## 5. 解码
```bash
python tools/decode_cap_mem.py capture_20260910.txt --labels owner,stop,left,right,forward,stranger --reps 3
```
输出:
- `data/replay_cap/{label}_cap.mem` — 13 行 hex 模板(每维 int16, dim0 起)
- 每组的 `208'h...` 字面量 — 可直接替换 `speaker_verify.v` / `cmd_matcher.v` 的参数默认值
- 距离报告: 组内 L1 距离(该词说 N 遍的稳定性) → **SPK_TH 下界**

## 6. 定 SPK_TH(诚实口径)
- `max_own` = 属主词组内最大距离。SPK_TH 必须 > max_own, 否则属主自己触发不了。
- 冒充者距离来自第 6 组: 对冒充者每个词段均值, 算到 owner 模板的 L1 距离, 记 `min_imp`。
- 若 `min_imp - max_own` 裕量足够(> ~1000), 取 TH 中点; 否则说明模板/特征区分度不够,
  **不要靠调 TH 假装好看** —— 那是板子真实能力, 如实记录 FAR/FRR 数据缺口。
- 当前默认 `SPK_TH=5000` 是占位值, 必须用本流程数据替换。

## 7. 重建调试固件(采集完成后)
把 `*.mem` 重新内嵌成 RTL 参数字面量(见 `reports/board_bringup_cmdfix.md` 的口径),
把 `top_voice_robot.v` 改回 `CAP_UART=0, VDBG_UART=1`, 重新综合+布局布线, 恢复 [AB] 调试帧验证。
