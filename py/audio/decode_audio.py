# -*- coding: utf-8 -*-
"""decode_audio.py — 统一 m4a→48kHz PCM 工具 + 数据集清单(metadata.csv)
  功能:
    1) 扫描 E:\electronic-circuit\sounds (owner_sound[含 commands/*], stranger1, stranger2)
    2) 用 PyAV 解码每个 m4a → 48k int16 stereo (L/R 保留)，取 L 声道作特征/回放
    3) 统计: duration / peak / rms / clipping / silence 写入 data/replay/metadata.csv
    4) 输出回放 PCM: data/replay_pcm/<group>/<stem>.pcm
       —— 24-bit 有符号小端 单声道 L = (int16 << 8)  与 RTL 24-bit 输入同量纲，
       保证与 audio_golden 的 int16 镜像(shift<<8) 逐位一致。
  原始 sounds/ 不改动。
"""
import os, sys, csv, glob
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))            # py/
import audio_golden as ag

ROOT = os.path.join(HERE, "..", "..")
SOUNDS = os.path.join(ROOT, "sounds")
OUT_CSV = os.path.join(ROOT, "data", "replay", "metadata.csv")
OUT_PCM = os.path.join(ROOT, "data", "replay_pcm")

SR = 48000
load_mono = ag.load_mono

def clip_frac(x16):
    ax = np.abs(x16.astype(np.int32))
    return float(np.mean(ax >= 32000))          # 接近满刻度比例

def silence_frac(x16, floor=60.0):
    n = (x16.size // 64) * 64
    if n == 0:
        return 1.0
    fr = x16[:n].astype(np.float64).reshape(-1, 64)
    rms = np.sqrt((fr ** 2).mean(axis=1))
    return float(np.mean(rms < floor))

def i24_le(s16):
    """int16<<8 → 24-bit int，写小端 3 字节。"""
    i24 = s16.astype(np.int64) << 8
    i24 = np.clip(i24, -(1 << 23), (1 << 23) - 1).astype(np.int32)
    b = np.empty((i24.size, 3), np.uint8)
    b[:, 0] = (i24 & 0xFF)
    b[:, 1] = (i24 >> 8) & 0xFF
    b[:, 2] = (i24 >> 16) & 0xFF
    return b.tobytes()

def main():
    rows = []
    os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)
    n_pcm = 0
    groups = [("owner_sound", "owner"),
              ("stranger1", "stranger1"),
              ("stranger2", "stranger2")]
    # owner 命令目录
    cmd_map = {}
    cmd_dir = os.path.join(SOUNDS, "owner_sound", "commands")
    if os.path.isdir(cmd_dir):
        for cmd in ["forward", "left", "right", "stop"]:
            d = os.path.join(cmd_dir, cmd)
            for f in glob.glob(os.path.join(d, "*.m4a")):
                cmd_map[f] = cmd

    files = []
    for g, st in groups:
        base = os.path.join(SOUNDS, g)
        if not os.path.isdir(base):
            continue
        for f in sorted(glob.glob(os.path.join(base, "*.m4a"))):
            files.append((f, g, st, "unknown"))
        # 顶层普通录音与命令子目录分开：commands 单独处理
    for f, cmd in cmd_map.items():
        files.append((f, "owner_cmds", "owner", cmd))

    for path, group, spk_type, command in files:
        L, R = load_mono(path)
        if L.size == 0:
            rows.append(dict(file=os.path.basename(path), path=path, speaker=group,
                             speaker_type=spk_type, command=command, sample_rate=SR,
                             channels=2, duration=0.0, peak=0.0, rms=0.0,
                             clipping=0.0, silence=1.0, source="m4a", note="DECODE_EMPTY"))
            continue
        dur = L.size / SR
        rms = float(np.sqrt(np.mean(L.astype(np.float64) ** 2)))
        peak = float(np.max(np.abs(L.astype(np.int32)))) if L.size else 0.0
        rows.append(dict(file=os.path.basename(path), path=path, speaker=group,
                         speaker_type=spk_type, command=command, sample_rate=SR,
                         channels=2, duration=round(dur, 3), peak=round(peak, 1),
                         rms=round(rms, 1), clipping=round(clip_frac(L), 5),
                         silence=round(silence_frac(L), 4), source="m4a", note=""))
        # 回放 PCM 24-bit mono L
        od = os.path.join(OUT_PCM, group)
        os.makedirs(od, exist_ok=True)
        stem = os.path.splitext(os.path.basename(path))[0]
        if group == "owner_cmds":
            od2 = os.path.join(od, command)
            os.makedirs(od2, exist_ok=True)
            p = os.path.join(od2, stem + ".pcm")
        else:
            p = os.path.join(od, stem + ".pcm")
        with open(p, "wb") as fh:
            fh.write(i24_le(L))
        n_pcm += 1

    cols = ["file", "path", "speaker", "speaker_type", "command", "sample_rate",
            "channels", "duration", "peak", "rms", "clipping", "silence", "source", "note"]
    with open(OUT_CSV, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    from collections import Counter
    c = Counter((r["speaker"], r["command"]) for r in rows)
    print("== 数据集清单 ==")
    for k in sorted(c):
        print(f"  {k[0]:>11} cmd={k[1]:<9} -> {c[k]} 条")
    print("pcm files written:", n_pcm)
    print("metadata ->", OUT_CSV)

if __name__ == "__main__":
    main()
