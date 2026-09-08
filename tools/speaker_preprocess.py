# -*- coding: utf-8 -*-
"""speaker_preprocess.py — 真实 m4a → 每文件特征 npz（B4 Golden，13×int16，energy 门去静音）
用法: python tools/speaker_preprocess.py [--sounds ../sounds] [--out ../data/speaker_features]
输出: <out>/<speaker>/<stem>.npz {features:int16[F,13], frame_total, frame_active, sr}
"""
import os, sys, glob, argparse
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "py"))
import audio_golden as ag

ROOT = os.path.join(os.path.dirname(__file__), "..")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sounds", default=os.path.join(ROOT, "sounds"))
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "speaker_features"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    total = 0
    for spk in sorted(os.listdir(a.sounds)):
        d = os.path.join(a.sounds, spk)
        if not os.path.isdir(d):
            continue
        od = os.path.join(a.out, spk)
        os.makedirs(od, exist_ok=True)
        for f in sorted(glob.glob(os.path.join(d, "*"))):
            if not f.lower().endswith((".m4a", ".wav", ".aac", ".mp4")):
                continue
            L, _R = ag.load_mono(f)               # 默认 L 声道；R 保留
            feats, tot, act, _ = ag.features_of(L)
            stem = os.path.splitext(os.path.basename(f))[0]
            np.savez(os.path.join(od, stem + ".npz"), features=feats.astype(np.int16),
                     frame_total=np.int64(tot), frame_active=np.int64(act), sr=np.int64(48000))
            total += feats.shape[0]
            print(f"{spk:>12} {stem} tot={tot:6d} act={act:6d} -> {feats.shape}")
    print("active frames total:", total)


if __name__ == "__main__":
    main()
