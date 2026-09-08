# -*- coding: utf-8 -*-
"""build_speaker_template.py — 主人模板：registration owner 录音 active 帧均值 → int16 → mem
用法: python tools/build_speaker_template.py
输出: data/speaker/owner_template.mem (13 行 s16 hex4)；data/speaker/split.json(reg/test 划分)
70% registration / 30% test（确定性 sorted 前 70% 注册，剩余测试；同一文件不同帧不跨集合）
"""
import os, sys, glob, json, math
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
FEAT = os.path.join(ROOT, "data", "speaker_features", "owner_sound")
OUTD = os.path.join(ROOT, "data", "speaker")
os.makedirs(OUTD, exist_ok=True)


def s16(v):
    v = int(round(v))
    v = max(-32768, min(32767, v))
    return v & 0xFFFF


def main():
    files = sorted(glob.glob(os.path.join(FEAT, "*.npz")))
    n = len(files)
    nr = max(1, int(math.ceil(0.7 * n)))
    reg, tst = files[:nr], files[nr:]
    regs = []
    for f in reg:
        z = np.load(f)
        regs.append(z["features"].astype(np.int64))
    F = np.concatenate(regs, axis=0)
    tpl = np.round(F.mean(axis=0)).astype(np.int64)
    tpl = np.clip(tpl, -32768, 32767)
    mem = "\n".join(f"{s16(v):04x}" for v in tpl)
    with open(os.path.join(OUTD, "owner_template.mem"), "w") as fo:
        fo.write(mem + "\n")
    with open(os.path.join(OUTD, "split.json"), "w", encoding="utf-8") as fo:
        json.dump({"reg": [os.path.basename(x) for x in reg],
                   "test": [os.path.basename(x) for x in tst]}, fo, indent=1)
    print(f"owner files={n} reg={len(reg)} test={len(tst)} reg_frames={F.shape[0]}")
    print("template int16:", tpl.tolist())
    print("mem:", os.path.join(OUTD, "owner_template.mem"))


if __name__ == "__main__":
    main()
