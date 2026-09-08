# -*- coding: utf-8 -*-
"""gen_command_templates.py — 扫描命令文件夹生成每命令 13-D MFCC 均值模板(.mem)
目录约定: sounds/commands/<cmd_name>/*.(wav|m4a)
输出: data/commands/cmd_<name>.mem (vtmpl 格式: 13 行 signed16 hex4)
无命令数据时会明确提示（不伪造）。打印每个命令均值便于核对。
用法: python tools/gen_command_templates.py
"""
import os, sys, glob
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
from audio_golden import load_mono, features_of


def read_tpl_int16(arr):
    # arr: float/int mean → round→clip→int16 (两补存 hex4)
    v = np.clip(np.round(np.asarray(arr, dtype=np.float64)), -32768, 32767).astype(np.int64)
    return [int(x) & 0xFFFF for x in v]


def main():
    cmd_dir = os.path.join(ROOT, "sounds", "commands")
    out_dir = os.path.join(ROOT, "data", "commands")
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.isdir(cmd_dir):
        sys.exit(f"未找到命令目录 {cmd_dir}。请先放 sounds/commands/<命令名>/*.{wav,m4a}。")
    total = 0
    for name in sorted(os.listdir(cmd_dir)):
        d = os.path.join(cmd_dir, name)
        if not os.path.isdir(d):
            continue
        feats = []
        for f in sorted(glob.glob(os.path.join(d, "*"))):
            if not f.lower().endswith((".wav", ".m4a")):
                continue
            x16, _ = load_mono(f, 48000)
            fmat, tot, act, _ = features_of(x16)
            if act == 0:
                continue
            feats.append(fmat.mean(0))
        if not feats:
            print(name, ": no active frames")
            continue
        mean = np.mean(feats, 0)
        mem = "\n".join("%04x" % v for v in read_tpl_int16(mean))
        with open(os.path.join(out_dir, f"cmd_{name}.mem"), "w") as fo:
            fo.write(mem + "\n")
        total += 1
        print(name, "files=%d mean=%s" % (len(feats), [int(x) for x in np.round(mean)]))
    print("templates written:", total, "->", out_dir)


if __name__ == "__main__":
    main()
