# -*- coding: utf-8 -*-
"""gen_command_templates.py — 命令文件夹 → 每命令 13-D MFCC 均值模板(.mem)
VAD(默认): 25ms/10ms 帧 RMS，语音帧 = RMS>=0.05*峰值；只取语音帧 MFCC 均值。
--no_vad: 整段均值(fallback)。目录约定 sounds/commands/<cmd>/*.{wav,m4a}
输出 data/commands/cmd_<name>.mem (vtmpl: 13 行 signed16 hex4)
"""
import os, sys, glob, argparse
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
import audio_golden as ag


def _vad_speech_frames(x16, win=1200, hop=480, frac=0.05):
    """x16 int16 → (int24 语音帧 rows[N,64]) 依据 25ms/10ms 能量门。"""
    L = x16.shape[0]
    nf = L // ag.N
    if nf == 0:
        return None, nf, 0
    w = x16.astype(np.float64)
    nwin = 1 + max(0, (L - win) // hop)
    e = np.array([np.sqrt((w[i * hop:i * hop + win] ** 2).mean()) for i in range(nwin)])
    thr = (e.max() * frac) if e.size else 0.0
    flags = e >= thr
    mask = np.zeros(L, bool)
    for i in range(nwin):
        if flags[i]:
            s, e2 = i * hop, min(i * hop + win, L)
            mask[s:e2] = True
    sel = np.array([mask[f * ag.N:(f + 1) * ag.N].any() for f in range(nf)])
    x24 = x16[:nf * ag.N].astype(np.int64) << 8
    act = x24.reshape(nf, ag.N)[sel]
    return act, nf, int(sel.sum())


def _mfcc16(rows):
    """rows int24 [F,64] → int16 features [F,13]（B4 链，逐位一致）。"""
    pe = ag._preemph_batch(rows)
    w = ag._window_batch(pe)
    re, im = ag._fft_batch(w)
    mel = ag._mel_batch(re, im)
    logm = ag._log_batch(mel)
    dct = ag._dct_batch(logm)
    return ag.feat16(dct)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no_vad", action="store_true", help="不做能量门，整段取均值")
    a = ap.parse_args()
    cmd_dir = os.path.join(ROOT, "sounds", "owner_sound", "commands")
    out_dir = os.path.join(ROOT, "data", "commands")
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.isdir(cmd_dir) or not os.listdir(cmd_dir):
        sys.exit("未找到命令目录 %s（请先放 sounds/commands/<cmd>/*.{wav,m4a}）。" % cmd_dir)
    for name in sorted(os.listdir(cmd_dir)):
        d = os.path.join(cmd_dir, name)
        if not os.path.isdir(d):
            continue
        feats = []
        ratio = 0.0
        for f in sorted(glob.glob(os.path.join(d, "*"))):
            if not f.lower().endswith((".wav", ".m4a")):
                continue
            x16, _ = ag.load_mono(f, 48000)
            if a.no_vad:
                act = x16[: (x16.shape[0] // ag.N) * ag.N].astype(np.int64).reshape(-1, ag.N) << 8
                tot = act.shape[0]; nact = tot
            else:
                act, tot, nact = _vad_speech_frames(x16)
                if act is None or act.shape[0] == 0:
                    print(name, os.path.basename(f), "no speech frames")
                    continue
            feats.append(_mfcc16(act))
            ratio = nact / tot if tot else 0.0
            print(f"  {name}/{os.path.basename(f)} 语音帧占比 {ratio:.2f} 有效 {nact}/{tot}")
        if not feats:
            print(name, ": no frames")
            continue
        mean = np.mean(np.concatenate(feats, 0), 0)
        mean16 = np.clip(np.round(mean), -32768, 32767).astype(np.int64)
        mem = "\n".join("%04x" % (int(v) & 0xFFFF) for v in mean16)
        with open(os.path.join(out_dir, f"cmd_{name}.mem"), "w") as fo:
            fo.write(mem + "\n")
        print(name, "模板写入 data/commands/cmd_%s.mem, 均值=" % name,
              [int(v) for v in mean16])


if __name__ == "__main__":
    main()
