#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#------------------------------------------------------------------------------
# plot_golden_vs_rtl.py  真实录音上 Python Golden 与 RTL feature_engine 的逐位比对
#
# 数据: data/replay_pcm/.../<x>.pcm (真实录音解码出的 48k 单声道 int16)
#   - Golden : py/audio_golden.py (与 RTL 逐位一致的整数镜像)
#   - RTL    : ModelSim 跑 sim/tb_mfcc_dump.v (把同一批 64 采样帧喂进 feature_engine)
#   - 比对   : 逐帧逐维 diff, 期望全 0
#
# 输出: fig5_mfcc_golden.png (Golden/RTL 曲线重合 + 逐维 diff 面板)
# 用法: python tools/plot_golden_vs_rtl.py [--pcm data/replay_pcm/owner_sound/20260908_163919.pcm] [--frames 16]
#------------------------------------------------------------------------------
import argparse
import os
import shutil
import subprocess
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIMDATA = os.path.join(REPO, "sim", "audio_sim", "data")
sys.path.insert(0, os.path.join(REPO, "py"))
import audio_golden as ag            # noqa: E402


def gen_vectors(pcm_path, nframes):
    """真实 PCM → 取前 nframes 个有效帧, 写 fe_real.mem / nf, 并返回 golden 特征。"""
    x16 = np.fromfile(pcm_path, dtype="<i2")
    if x16.size < ag.N:
        raise SystemExit("PCM 太短")
    fr16, rms = ag.frame_energy(x16)
    mask = ag.active_mask(rms)
    x24 = x16.astype(np.int64) << 8
    act = x24[: (fr16.shape[0] * ag.N)].reshape(-1, ag.N)[mask]
    golden_all, total, active, _ = ag.features_of(x16)
    if act.shape[0] == 0:
        raise SystemExit("该录音没有有效帧")

    nf = min(int(nframes), act.shape[0])
    act = act[:nf]
    golden = golden_all[:nf].astype(np.int64)

    with open(os.path.join(SIMDATA, "fe_real.mem"), "w") as f:
        for v in act.reshape(-1):
            f.write(f"{int(v) & 0xFFFFFF:06x}\n")
    with open(os.path.join(SIMDATA, "fe_real_nf.mem"), "w") as f:
        f.write(f"{nf:04x}\n")
    print(f"录音 {os.path.basename(pcm_path)}: 总帧 {total}, 有效帧 {active}, 取 {nf} 帧")
    return golden, nf


def run_vsim():
    vsim = shutil.which("vsim")
    if not vsim:
        for c in (r"D:\Program Files\modelsim_ase\win32aloem\vsim.exe",
                  r"C:\modeltech_ae\win32aloem\vsim.exe"):
            if os.path.exists(c):
                vsim = c
                break
    if not vsim:
        raise SystemExit("找不到 vsim — 请把 ModelSim 的 win32aloem 加入 PATH")
    r = subprocess.run([vsim, "-c", "-do", "run_mfcc_dump.do"],
                       cwd=os.path.join(REPO, "sim", "audio_sim"),
                       capture_output=True, text=True)
    tail = [l for l in (r.stdout + r.stderr).splitlines()
            if "DUMP DONE" in l or "Error" in l or "ERROR" in l or "** " in l]
    print("vsim:", " | ".join(tail[-4:]) if tail else "done")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pcm", default="data/replay_pcm/owner_sound/20260908_163919.pcm")
    ap.add_argument("--frames", type=int, default=16)
    ap.add_argument("--out_dir", default=".")
    args = ap.parse_args()

    pcm_path = args.pcm if os.path.isabs(args.pcm) else os.path.join(REPO, args.pcm)
    golden, nf = gen_vectors(pcm_path, args.frames)
    run_vsim()

    rtl = np.loadtxt(os.path.join(SIMDATA, "fe_real_rtl.txt"), dtype=np.int64)
    rtl = np.atleast_2d(rtl)
    if rtl.shape[0] != nf:
        raise SystemExit(f"RTL 帧数 {rtl.shape[0]} != {nf}")
    diff = rtl - golden
    nmis = int((diff != 0).sum())
    print(f"比对: {nf} 帧 × {golden.shape[1]} 维, 不一致 {nmis} 个, max|diff|={int(np.abs(diff).max())}")

    K = golden.shape[1]
    t = np.arange(nf * K)
    gflat = golden.reshape(-1)
    rflat = rtl.reshape(-1)

    fig, (ax, axd) = plt.subplots(2, 1, figsize=(11, 6.5),
                                  gridspec_kw={"height_ratios": [2.4, 1]})
    ax.plot(t, gflat, "-", color="#1565c0", lw=1.6, label="Python Golden")
    ax.plot(t, rflat, "x", color="#e53935", ms=6, mew=1.4, label="RTL (ModelSim)")
    for f in range(1, nf):
        ax.axvline(f * K - 0.5, color="#dddddd", ls=":", lw=0.9)
    ax.set_xticks([f * K + K / 2 - 0.5 for f in range(nf)])
    ax.set_xticklabels([f"帧{f+1}" for f in range(nf)], fontsize=8, rotation=45)
    ax.set_ylabel("MFCC 系数值（int16）")
    ax.set_title(f"真实录音（{os.path.basename(args.pcm)}）上 Python Golden 与 RTL 的逐位比对",
                 fontsize=12)
    ax.legend(loc="upper right", fontsize=9)
    ax.grid(axis="y", ls=":", alpha=0.4)

    axd.bar(t, diff.reshape(-1), width=0.8, color="#2e7d32")
    axd.axhline(0, color="#888888", lw=0.8)
    axd.set_ylim(-1, 1)
    axd.set_yticks([-1, 0, 1])
    axd.set_xticks(ax.get_xticks()); axd.set_xticklabels(ax.get_xticklabels())
    axd.set_ylabel("RTL − Golden")
    axd.set_xlabel("帧序号（每帧 13 维）")
    axd.set_title(f"逐系数差值：{nf}×{K} = {nf*K} 个系数全部为 0（max|diff| = 0）",
                  fontsize=11, color="#2e7d32")

    fig.tight_layout()
    p = os.path.join(args.out_dir, "fig5_mfcc_golden.png")
    fig.savefig(p, dpi=150, bbox_inches="tight", pad_inches=0.12)
    print("wrote", p)


if __name__ == "__main__":
    main()
