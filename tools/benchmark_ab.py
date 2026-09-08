# -*- coding: utf-8 -*-
"""benchmark_ab.py — A(原 MFCC13+L1) vs B(CAM++ cosine) 声纹基线对比
用法:
  python tools/benchmark_ab.py            # A 臂真实数据；B 臂需 campplus_emb.onnx
    [--feat data/speaker_features] [--tpl data/speaker/owner_template.mem]
    [--split data/speaker/split.json] [--sounds sounds]
输出: reports/comparison_campplus_vs_mfcc.csv (+ 控制台 EER)
诚实原则：B 臂模型缺失则明确失败，不伪造数字。
"""
import os, sys, json, glob, csv
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))

def read_tpl16(p):
    vals = []
    for l in open(p):
        l = l.strip()
        if l:
            v = int(l, 16)
            vals.append(v - 0x10000 if v & 0x8000 else v)
    return np.array(vals, np.int64)


def l1(a, b):
    return int(np.abs(np.asarray(a) - np.asarray(b)).sum())


def rec_score_mean_mfcc(npz):
    """录音级 MFCC 代表 = 活动帧均值(round/clip int16)。"""
    f = np.load(npz)["features"].astype(np.int64)
    return np.clip(np.round(f.mean(0)), -32768, 32767).astype(np.int64)


def eer(scores_pos, scores_neg, higher_better=True):
    """返回 (EER, threshold)。"""
    lo = min(np.min(scores_pos) if len(scores_pos) else 0,
             np.min(scores_neg) if len(scores_neg) else 0)
    hi = max(np.max(scores_pos) if len(scores_pos) else 0,
             np.max(scores_neg) if len(scores_neg) else 0)
    best = (1.0, lo)
    for t in np.linspace(lo, hi, 2000):
        if higher_better:
            far = np.mean(scores_neg >= t); frr = np.mean(scores_pos < t)
        else:
            far = np.mean(scores_neg <= t); frr = np.mean(scores_pos > t)
        e = abs(far - frr)
        if e < best[0]:
            best = (e, float(t))
    return best


def main():
    args = dict(zip(
        ["--feat", "--tpl", "--split", "--sounds"],
        [os.path.join(ROOT, "data", "speaker_features"),
         os.path.join(ROOT, "data", "speaker", "owner_template.mem"),
         os.path.join(ROOT, "data", "speaker", "split.json"),
         os.path.join(ROOT, "sounds")]))
    tpl = read_tpl16(args["--tpl"])
    split = json.load(open(args["--split"], encoding="utf-8"))

    tst = set(split["test"])
    reg = set(split["reg"])
    own_all = sorted(glob.glob(os.path.join(args["--feat"], "owner_sound", "*.npz")))
    own = [p for p in own_all if os.path.basename(p) in tst]
    reg_files = [p for p in own_all if os.path.basename(p) in reg]
    imp = []
    for spk in ("stranger1", "stranger2"):
        imp += sorted(glob.glob(os.path.join(args["--feat"], spk, "*.npz")))

    # ---- A 臂：MFCC 录音级 L1 ----
    A_own = [l1(rec_score_mean_mfcc(f), tpl) for f in own]
    A_imp = [l1(rec_score_mean_mfcc(f), tpl) for f in imp]
    e_a = eer(A_own, A_imp, higher_better=False)
    rows = []
    for f, d in zip(own, A_own):
        rows.append(["owner", os.path.basename(f), "mfcc_L1", "", d, ""])
    for f, d in zip(imp, A_imp):
        rows.append(["impostor", os.path.basename(f), "mfcc_L1", "", d, ""])

    # ---- B 臂：CAM++ cosine（需模型）----
    B_note = "unavailable"
    try:
        from campplus.interface import extract_embedding, verify_speaker
        # 需要把 m4a 路径映射到 owner/stranger
        def audio_of(stem, spk):
            p = os.path.join(args["--sounds"], spk, stem + ".m4a")
            return p if os.path.exists(p) else None
        reg = json.load(open(args["--split"], encoding="utf-8"))["reg"]
        reg_emb = []
        for f in reg:
            a = audio_of(f[:-4], "owner_sound")
            if a:
                reg_emb.append(extract_embedding(a))
        tpl_emb = np.mean(reg_emb, 0)
        tpl_emb /= (np.linalg.norm(tpl_emb) or 1)
        B_own = [verify_speaker(extract_embedding(audio_of(os.path.basename(f)[:-4], "owner_sound")), tpl_emb) for f in own]
        B_imp = [verify_speaker(extract_embedding(audio_of(os.path.basename(f)[:-4], "stranger1" if "stranger1" in f else "stranger2")), tpl_emb) for f in imp]
        e_b = eer(B_own, B_imp, higher_better=True)
        B_note = f"ok eer={e_b[0]:.3f}"
    except FileNotFoundError as ex:
        B_note = "unavailable: " + str(ex).splitlines()[0]
    except Exception as ex:
        B_note = "error: " + repr(ex)

    print("== A arm MFCC recording-level ==")
    print("owner dist:", [int(x) for x in A_own])
    print("impostor dist:", [int(x) for x in A_imp])
    print("A EER:", e_a)
    print("== B arm CAM++ ==")
    print("B:", B_note)

    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    with open(os.path.join(ROOT, "reports", "comparison_campplus_vs_mfcc.csv"), "w", newline="") as fo:
        w = csv.writer(fo)
        w.writerow(["speaker", "file", "method", "A_dist", "B_sim", "note"])
        w.writerows(rows)
    print("csv -> reports/comparison_campplus_vs_mfcc.csv ; B:", B_note)


if __name__ == "__main__":
    main()
