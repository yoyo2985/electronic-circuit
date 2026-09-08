# -*- coding: utf-8 -*-
"""evaluate_speaker_verification.py — 真实 owner/impostor L1 分布 + FAR/FRR/阈值
用法: python tools/evaluate_speaker_verification.py
输出: reports/speaker_verification/threshold_results.csv, *_report.txt,
      data/speaker/owner_template.mem 已由 build 生成；本脚本读取。
"""
import os, sys, json, glob
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
SPK = os.path.join(ROOT, "data", "speaker")
REP = os.path.join(ROOT, "reports", "speaker_verification")
os.makedirs(REP, exist_ok=True)


def read_tpl():
    vals = []
    with open(os.path.join(SPK, "owner_template.mem")) as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                vals.append(v - 0x10000 if v & 0x8000 else v)
    return np.array(vals, dtype=np.int64)


def load_feats(speaker, files):
    out = []
    for f in files:
        z = np.load(os.path.join(ROOT, "data", "speaker_features", speaker, f))
        out.append(z["features"].astype(np.int64))
    return np.concatenate(out, 0) if out else np.zeros((0, 13), np.int64)


def l1(F, t):
    return np.abs(F - t[None, :]).sum(axis=1)


def main():
    t = read_tpl()
    with open(os.path.join(SPK, "split.json"), encoding="utf-8") as f:
        split = json.load(f)
    otest = load_feats("owner_sound", split["test"])
    strangers = []
    for spk in ("stranger1", "stranger2"):
        files = sorted(os.path.basename(x) for x in
                       glob.glob(os.path.join(ROOT, "data", "speaker_features", spk, "*.npz")))
        strangers.append(load_feats(spk, files))
    imp = np.concatenate(strangers, 0) if strangers else np.zeros((0, 13), np.int64)
    d_own = l1(otest, t).astype(np.int64)
    d_imp = l1(imp, t).astype(np.int64)
    lo = min(d_own.min() if d_own.size else 0, d_imp.min() if d_imp.size else 0)
    hi = max(d_own.max() if d_own.size else 0, d_imp.max() if d_imp.size else 0)
    lines = []
    lines.append(f"owner_test frames={d_own.size} impostor frames={d_imp.size}")
    if d_own.size:
        lines.append("owner dist: mean=%.1f std=%.1f min=%d med=%.0f p95=%d p99=%d"
                     % (d_own.mean(), d_own.std(), d_own.min(), np.median(d_own),
                        np.percentile(d_own, 95), np.percentile(d_own, 99)))
    if d_imp.size:
        lines.append("impostor dist: mean=%.1f std=%.1f min=%d med=%.0f p1=%d p5=%d p10=%d"
                     % (d_imp.mean(), d_imp.std(), d_imp.min(), np.median(d_imp),
                        np.percentile(d_imp, 1), np.percentile(d_imp, 5), np.percentile(d_imp, 10)))
    # sweep
    THs = np.arange(lo, hi + 2000, 500, dtype=np.int64)
    rows = []
    cand = {}
    for TH in THs:
        fp = int(np.sum(d_imp <= TH)) if d_imp.size else 0
        tn = d_imp.size - fp
        fn = int(np.sum(d_own > TH)) if d_own.size else 0
        tp = d_own.size - fn
        far = fp / d_imp.size if d_imp.size else 0.0
        frr = fn / d_own.size if d_own.size else 0.0
        acc = (tp + tn) / (d_own.size + d_imp.size) if (d_own.size + d_imp.size) else 0.0
        rows.append((TH, tp, tn, fp, fn, far, frr, acc))
        if far == 0.0 and "far0" not in cand:
            cand["far0"] = (int(TH), frr)
        if far <= 0.01 and "far1" not in cand:
            cand["far1"] = (int(TH), frr)
        if far <= 0.05 and "far5" not in cand:
            cand["far5"] = (int(TH), frr)
    best = min(rows, key=lambda r: abs(r[5] - r[6])) if rows else None
    cand["best_acc"] = max(rows, key=lambda r: r[7])[:2] if rows else None

    lines.append("候选工作点:")
    for k in ("far0", "far1", "far5"):
        if k in cand:
            th, frr = cand[k]
            lines.append(f"  FAR<=0/1%/5% -> TH={th} FRR={frr:.3%}")
    if best:
        lines.append("EER 近似(best_bal TH=%d far=%.3f frr=%.3f)" % (best[0], best[5], best[6]))
    lines.append("推荐(低FAR): TH=%d (FAR=0 时最小 FRR=%s)"
                 % (cand.get("far0", (hi + 1, 1.0))[0],
                    ("%.1f%%" % (cand["far0"][1] * 100)) if "far0" in cand else "n/a"))

    import csv
    with open(os.path.join(REP, "threshold_results.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["TH", "TP", "TN", "FP", "FN", "FAR", "FRR", "accuracy"])
        w.writerows(rows)
    with open(os.path.join(REP, "evaluate_report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
