#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#------------------------------------------------------------------------------
# plot_speaker_roc.py  真实录音声纹评估的 ROC / DET 曲线
#
# 真实数据:
#   A(MFCC13+L1) : 由 data/speaker_features/*/*.npz(真实录音的逐帧 13 维 MFCC)
#                  现算: 每条录音取帧均值 → 与主人模板 L1 距离(full 与 leave-one-out)。
#   B(CAM++ cos) : reports/comparison_campplus_vs_mfcc[_loo].csv 中真实 CAM++ 打分。
#
# 说明: reports/comparison_summary.txt 里印的 "EER" 实为 benchmark_ab.py 中
#       eer() 返回的 min|FAR-FRR|(曲线与对角线相交处), 并非 EER 数值;
#       本脚本用 roc_curve 重新计算真正的 EER。
#
# 输出: fig7_roc_det.png (左 ROC / 右 DET, full 与 LOO, A 与 B)
# 用法: python tools/plot_speaker_roc.py [--out_dir .]
#------------------------------------------------------------------------------
import argparse
import csv
import glob
import os

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve
from scipy.stats import norm

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEAT = os.path.join(ROOT, "data", "speaker_features")


def rec_mean_mfcc(npz):
    f = np.load(npz)["features"].astype(np.int64)
    return np.clip(np.round(f.mean(0)), -32768, 32767).astype(np.int64)


def l1(a, b):
    return int(np.abs(np.asarray(a) - np.asarray(b)).sum())


def eer_of(pos, neg):
    """pos/neg 为已定向的分数(越大越像主人)。返回真正 EER。"""
    y = np.concatenate([np.ones(len(pos)), np.zeros(len(neg))])
    s = np.concatenate([np.asarray(pos, float), np.asarray(neg, float)])
    fpr, tpr, _ = roc_curve(y, s)
    fnr = 1.0 - tpr
    i = int(np.argmin(np.abs(fpr - fnr)))
    return 0.5 * (float(fpr[i]) + float(fnr[i]))


def mfcc_scores():
    own = sorted(glob.glob(os.path.join(FEAT, "owner_sound", "*.npz")))
    imp = []
    for s in ("stranger1", "stranger2"):
        imp += sorted(glob.glob(os.path.join(FEAT, s, "*.npz")))
    A = {os.path.basename(f): rec_mean_mfcc(f) for f in own + imp}
    on = [os.path.basename(f) for f in own]
    ind = [os.path.basename(f) for f in imp]

    tA = np.clip(np.round(np.mean([A[n] for n in on], 0)), -32768, 32767)
    full_pos = [l1(A[n], tA) for n in on]
    full_neg = [l1(A[n], tA) for n in ind]

    loo_pos, loo_neg = [], []
    for o in on:
        others = [n for n in on if n != o]
        t = np.clip(np.round(np.mean([A[n] for n in others], 0)), -32768, 32767)
        loo_pos.append(l1(A[o], t))
        for n in ind:
            loo_neg.append(l1(A[n], t))
    return full_pos, full_neg, loo_pos, loo_neg


def campplus_scores(path):
    pos, neg = [], []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            (pos if row["label"] == "owner" else neg).append(float(row["B_sim"]))
    return pos, neg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out_dir", default=".")
    args = ap.parse_args()

    fA_p, fA_n, lA_p, lA_n = mfcc_scores()
    fB_p, fB_n = campplus_scores(os.path.join(ROOT, "reports/comparison_campplus_vs_mfcc.csv"))
    lB_p, lB_n = campplus_scores(os.path.join(ROOT, "reports/comparison_campplus_vs_mfcc_loo.csv"))

    curves = [
        ("full · MFCC13+L1", -np.array(fA_p, float), -np.array(fA_n, float), "#1565c0", "-"),
        ("full · CAM++ cos", np.array(fB_p, float), np.array(fB_n, float), "#ef6c00", "-"),
        ("LOO · MFCC13+L1", -np.array(lA_p, float), -np.array(lA_n, float), "#1565c0", "--"),
        ("LOO · CAM++ cos", np.array(lB_p, float), np.array(lB_n, float), "#ef6c00", "--"),
    ]

    fig, (axr, axd) = plt.subplots(1, 2, figsize=(12.5, 6))
    axr.plot([0, 1], [0, 1], color="#bbbbbb", ls=":", lw=1)
    axd.plot([-4, 4], [-4, 4], color="#bbbbbb", ls=":", lw=1)

    for name, pos, neg, col, ls in curves:
        y = np.concatenate([np.ones(len(pos)), np.zeros(len(neg))])
        s = np.concatenate([pos, neg])
        fpr, tpr, _ = roc_curve(y, s)
        e = eer_of(pos, neg)
        print(f"  {name:18s} n+={len(pos):3d} n-={len(neg):3d}  EER={e*100:5.1f}%")
        axr.plot(fpr, tpr, ls, color=col, lw=1.9, label=f"{name}  EER={e*100:.1f}%")
        cx = np.clip(fpr, 1e-5, 1 - 1e-5)
        cy = np.clip(1 - tpr, 1e-5, 1 - 1e-5)
        axd.plot(norm.ppf(cx), norm.ppf(cy), ls, color=col, lw=1.9, label=name)

    ticks = [0.001, 0.01, 0.05, 0.2, 0.5]
    labs = ["0.1", "1", "5", "20", "50"]
    axr.set_xlim(0, 1); axr.set_ylim(0, 1)
    axr.set_xlabel("虚警率 FAR"); axr.set_ylabel("命中率 TPR")
    axr.set_title("ROC 曲线", fontsize=12)
    axr.legend(loc="lower right", fontsize=9)
    axr.grid(ls=":", alpha=0.4)

    axd.set_xticks(norm.ppf(ticks)); axd.set_xticklabels(labs)
    axd.set_yticks(norm.ppf(ticks)); axd.set_yticklabels(labs)
    axd.set_xlim(-3.2, 3.2); axd.set_ylim(-3.2, 3.2)
    axd.set_xlabel("虚警率 FAR / %（正态概率轴）")
    axd.set_ylabel("漏检率 FRR / %（正态概率轴）")
    axd.set_title("DET 曲线", fontsize=12)
    axd.legend(loc="upper right", fontsize=9)
    axd.grid(ls=":", alpha=0.4)

    fig.suptitle("真实录音声纹评估：MFCC13+L1 与 CAM++（full 与 leave-one-out）", fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    p = os.path.join(args.out_dir, "fig7_roc_det.png")
    fig.savefig(p, dpi=150, bbox_inches="tight", pad_inches=0.12)
    print("wrote", p)


if __name__ == "__main__":
    main()
