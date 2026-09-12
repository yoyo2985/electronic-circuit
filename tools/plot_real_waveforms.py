#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#------------------------------------------------------------------------------
# plot_real_waveforms.py  基于板上真实采集数据的"仿真波形"图
#
# 数据来源: sounds/capture2_clean.txt (SSCOM 采集的 M-line, 每段 = 帧数 + 13 维
#           MFCC 段内和)。模板: data/speaker/owner_template.mem, data/commands/cmd_*.mem。
#
# 输出(写到 --out_dir, 默认仓库根, 供 report.tex 的 \insfig 直接引用):
#   fig6_speaker_waveform.png   声纹认证与段级决策(段均值 L1 + owner_valid 电平)
#   fig8_cmd_waveform.png       命令识别(各段到四类模板的 L1 + cmd_id 判决)
#   fig9_e2e_voice_waveform.png Who+What 联合决策(owner_valid/cmd_id/cmd_valid/action/target)
#
# 用法: python tools/plot_real_waveforms.py [--cap sounds/capture2_clean.txt] [--out_dir .]
#------------------------------------------------------------------------------
import argparse
import importlib.util
import os
from collections import OrderedDict

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

CMDS = ["stop", "left", "right", "forward"]          # cmd_id 0/1/2/3
CMD_CN = {"stop": "停止", "left": "左转", "right": "右转", "forward": "前进"}
CMD_COLOR = {"stop": "#1f77b4", "left": "#2ca02c", "right": "#d62728", "forward": "#9467bd"}
CMD_ID = {"stop": 0, "left": 1, "right": 2, "forward": 3}
ACT_CN = {0: "停止", 2: "前进", 3: "左转", 4: "右转"}
TH_OWN = 4300                                        # 与 rtl/seg_decide.v 一致


def _load_decode_mod():
    spec = importlib.util.spec_from_file_location(
        "dcm", os.path.join(os.path.dirname(__file__), "decode_cap_mem.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def s16(v):
    return v - 0x10000 if v >= 0x8000 else v


def load_mem(path):
    return [s16(int(x, 16)) for x in open(path, encoding="utf-8").read().split()]


def l1(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def logic_wave(ax, y, label, color, y0=0.0, h=1.0, lw=1.8, ls="-"):
    """把取值序列 y 画成阶梯电平波形, 基线 y0, 幅值 h。"""
    x = np.arange(len(y) + 1)
    yy = np.concatenate([[y[0]], y]) * h + y0
    ax.step(x, yy, where="post", color=color, lw=lw, ls=ls)
    ax.axhline(y0, color="#e0e0e0", lw=0.6, zorder=0)
    ax.text(-0.03 * len(y), y0 + 0.5 * h, label, ha="right", va="center", fontsize=10)
    ax.set_xlim(0, len(y))


# ---------------- 图 6: 声纹认证 + 段级决策 ----------------
def fig_speaker(fig, segs, owner_tpl, out_dir):
    ax = fig.add_subplot(2, 1, 1)
    axd = fig.add_subplot(2, 1, 2, sharex=ax)

    gen = [l1(owner_tpl, m) for m in segs["owner/owner"]]      # 属主
    imp = [l1(owner_tpl, m) for m in segs["imp/forward"]]      # 陌生人

    xg = np.arange(len(gen))
    xi = np.arange(len(gen), len(gen) + len(imp))
    ymax = max(max(gen), max(imp)) * 1.18

    ax.axhspan(0, TH_OWN, color="#e8f5e9", zorder=0)
    ax.axhspan(TH_OWN, ymax, color="#fdeaea", zorder=0)
    ax.axhline(TH_OWN, color="#c62828", ls="--", lw=1.5)
    ax.text(0.15, TH_OWN + ymax * 0.015, f"TH_OWN = {TH_OWN}", color="#c62828", fontsize=10)

    ax.vlines(xg, 0, gen, color="#1565c0", lw=2.4)
    ax.plot(xg, gen, "o", color="#1565c0", ms=6.5, label="属主（本人）")
    ax.vlines(xi, 0, imp, color="#c62828", lw=2.4)
    ax.plot(xi, imp, "s", color="#c62828", ms=6.5, label="陌生人（冒充）")
    for x, v in zip(xi, imp):
        ax.annotate(f"{v}", (x, v), textcoords="offset points", xytext=(0, 7),
                    ha="center", fontsize=8, color="#c62828")

    ax.axvline(len(gen) - 0.5, color="#999999", ls=":", lw=1.2)
    ax.set_ylim(0, ymax)
    ax.set_xticks(range(len(gen) + len(imp)))
    ax.set_xticklabels([f"属主{i+1}" for i in range(len(gen))] +
                       [f"陌生{i+1}" for i in range(len(imp))], fontsize=8, rotation=45)
    ax.set_ylabel("段均值 L1 距离")
    ax.set_title("基于真实采集（capture2 会话）的段级声纹认证", fontsize=12)
    ax.legend(loc="center left", fontsize=9)
    ax.grid(axis="y", ls=":", alpha=0.4)

    ov = [1 if d < TH_OWN else 0 for d in gen] + [1 if d < TH_OWN else 0 for d in imp]
    logic_wave(axd, ov, "owner_valid", "#2e7d32", y0=0.5)
    axd.set_yticks([]); axd.set_ylim(0, 1.2)
    axd.set_ylabel("段末判决")
    axd.set_xlabel("语音段序号（段末锁存）")
    axd.set_title("段级声纹判决电平：属主全部过闸、陌生人全部被拒", fontsize=11)
    for s in ("top", "right"):
        axd.spines[s].set_visible(False)

    fig.tight_layout()
    p = os.path.join(out_dir, "fig6_speaker_waveform.png")
    fig.savefig(p, dpi=150, bbox_inches="tight", pad_inches=0.12); print("wrote", p)


# ---------------- 图 8: 命令识别 ----------------
def fig_cmd(fig, segs, tmpl, out_dir):
    order = ["forward", "stop", "left", "right"]
    idx, labels, seps, groups = [], [], [], []
    pos = 0
    for w in order:
        seps.append(pos - 0.5)
        groups.append((pos, pos + len(segs[f"owner/{w}"]) - 1, w))
        for i in range(len(segs[f"owner/{w}"])):
            idx.append((w, i)); labels.append(f"{CMD_CN[w]}{i+1}"); pos += 1
    seps.append(pos - 0.5)

    D = {c: [] for c in CMDS}
    arg = []
    for w, i in idx:
        m = segs[f"owner/{w}"][i]
        d = {c: l1(tmpl[c], m) for c in CMDS}
        for c in CMDS:
            D[c].append(d[c])
        arg.append(min(CMDS, key=lambda c: d[c]))

    ax = fig.add_subplot(2, 1, 1)
    x = np.arange(len(idx))
    handles = []
    for c in CMDS:
        h, = ax.plot(x, D[c], "-o", color=CMD_COLOR[c], ms=3.5, lw=1.3, label=CMD_CN[c] + "模板")
        handles.append(h)
    for s in seps[1:-1]:
        ax.axvline(s, color="#bbbbbb", ls=":", lw=1.2)
    for xi, (w, i) in enumerate(idx):
        c = arg[xi]
        ax.plot(xi, D[c][xi], "o", color=CMD_COLOR[c], ms=8, mec="k", mew=1.0, zorder=5)
    ax.set_xticks(x); ax.set_xticklabels(labels, fontsize=8, rotation=45)
    ax.set_ylabel("段均值 L1 距离")
    ax.set_title("基于真实采集的命令识别：各段到四类模板的 L1 距离（实心点=argmin 判决）",
                 fontsize=12)
    ax.grid(axis="y", ls=":", alpha=0.4)

    axd = fig.add_subplot(2, 1, 2, sharex=ax)
    dec = [CMD_ID[c] for c in arg]
    tru = [CMD_ID[w] for w, _ in idx]
    hits = [d == t for d, t in zip(dec, tru)]
    for xi, ok in enumerate(hits):
        if not ok:
            axd.axvspan(xi - 0.5, xi + 0.5, color="#ffcdd2", alpha=0.8, zorder=0)
    axd.step(np.arange(len(tru) + 1), np.concatenate([[tru[0]], tru]),
             where="post", color="#9e9e9e", lw=1.4, ls="--", label="真值")
    axd.step(np.arange(len(dec) + 1), np.concatenate([[dec[0]], dec]),
             where="post", color="#1565c0", lw=2.0, label="判决 cmd_id")
    for s in seps[1:-1]:
        axd.axvline(s, color="#bbbbbb", ls=":", lw=1.2)
    for a, b, w in groups:
        axd.text((a + b) / 2, -0.75, CMD_CN[w], ha="center", va="top", fontsize=10)
    axd.set_yticks([0, 1, 2, 3])
    axd.set_yticklabels([CMD_CN[c] for c in CMDS], fontsize=9)
    axd.set_ylim(-1.1, 3.4)
    axd.set_xlabel("语音段（按真值词分组，红底=判决错误）")
    axd.set_title(f"命令判决波形：命中 {sum(hits)}/{len(hits)}（前进可分，左/右与停止存在混淆）",
                  fontsize=11)
    for s in ("top", "right"):
        axd.spines[s].set_visible(False)
    fig.legend(handles, [h.get_label() for h in handles],
               ncol=4, fontsize=9, loc="lower center", bbox_to_anchor=(0.5, 0.012))
    fig.tight_layout(rect=[0, 0.065, 1, 1])
    p = os.path.join(out_dir, "fig8_cmd_waveform.png")
    fig.savefig(p, dpi=150, bbox_inches="tight", pad_inches=0.12); print("wrote", p)


# ---------------- 图 9: Who+What 联合决策 ----------------
def fig_e2e(fig, segs, owner_tpl, tmpl, out_dir):
    # 显式选段(段索引): 陌生人前进(被拒) → 属主前进(执行) → 陌生人前进(被拒) → 属主停止
    seq = [("imp/forward", 1, "陌生人:前进"), ("imp/forward", 2, "陌生人:前进"),
           ("owner/forward", 0, "属主:前进"), ("owner/forward", 1, "属主:前进"),
           ("imp/forward", 3, "陌生人:前进"),
           ("owner/stop", 0, "属主:停止"), ("owner/stop", 1, "属主:停止")]

    owner_v, cmd_id, cmd_valid, action, target, dist = [], [], [], [], [], []
    tgt = 0
    for gk, j, _ in seq:
        m = segs[gk][j]
        d = l1(owner_tpl, m)
        ov = 1 if d < TH_OWN else 0
        cid = CMD_ID[min(CMDS, key=lambda c: l1(tmpl[c], m))]
        valid = 1 if (ov and gk.startswith("owner/")) else 0
        act = 0
        if valid:
            act = {0: 0, 3: 2, 1: 3, 2: 4}[cid]        # 0停/2前/3左/4右
            if act == 2:
                tgt = 90
            elif act == 3:
                tgt = 0
            elif act == 4:
                tgt = 180
        owner_v.append(ov); cmd_id.append(cid); cmd_valid.append(valid)
        action.append(act); target.append(tgt); dist.append(d)

    ax = fig.add_subplot(1, 1, 1)
    n = len(seq)
    logic_wave(ax, owner_v, "owner_valid", "#2e7d32", y0=6.2, h=0.9)
    logic_wave(ax, cmd_id, "cmd_id", "#1565c0", y0=3.6, h=0.55)
    logic_wave(ax, cmd_valid, "o_cmd_valid", "#ef6c00", y0=2.2, h=0.9)
    logic_wave(ax, action, "action", "#8e24aa", y0=0.4, h=0.35)
    logic_wave(ax, np.array(target) / 180.0, "target/180", "#c62828", y0=-1.5, h=1.0)
    for xi, v in enumerate(target):
        ax.text(xi + 0.5, -1.25, f"{v}", ha="center", fontsize=8, color="#c62828")
    for xi, v in enumerate(cmd_id):
        ax.text(xi + 0.5, 3.6 + v * 0.55 + 0.1, f"{CMD_ID_INV[v]}", ha="center",
                fontsize=7.5, color="#1565c0")
    for gi, (gk, j, lab) in enumerate(seq):
        ax.text(gi + 0.5, 7.5, lab, ha="center", fontsize=8.5)
        if gi > 0:
            ax.axvline(gi, color="#bbbbbb", ls=":", lw=1.0)
    ax.set_ylim(-2.3, 7.9); ax.set_yticks([]); ax.set_xlim(0, n)
    ax.set_xlabel("语音段序号（依次输入真实采集段；段末判决 / 目标为机器人关节角度 0°～180°）")
    ax.set_title("Who + What 联合决策波形：仅属主的有效命令改变机器人目标", fontsize=12)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)

    fig.tight_layout()
    p = os.path.join(out_dir, "fig9_e2e_voice_waveform.png")
    fig.savefig(p, dpi=150, bbox_inches="tight", pad_inches=0.12); print("wrote", p)
    print("  owner_dist:", dist, "owner_valid:", owner_v, "target:", target)


CMD_ID_INV = {0: "停", 1: "左", 2: "右", 3: "前"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap", default="sounds/capture2_clean.txt")
    ap.add_argument("--out_dir", default=".")
    args = ap.parse_args()

    dcm = _load_decode_mod()
    raw, _ = dcm.parse_log(args.cap)
    if not raw:
        raise SystemExit("未解析到有效段 — 检查采集日志格式")

    G = OrderedDict()
    for cnt, sums, gk in raw:
        G.setdefault(gk, []).append(dcm.seg_mean(cnt, sums))
    segs = dict(G)
    print("组:", {k: len(v) for k, v in segs.items()})

    owner_tpl = load_mem("data/speaker/owner_template.mem")
    same = {c: dcm.group_mean(segs[f"owner/{c}"]) for c in CMDS}   # 同会话模板

    fig_speaker(plt.figure(figsize=(11, 7)), segs, owner_tpl, args.out_dir)
    fig_cmd(plt.figure(figsize=(12, 8)), segs, same, args.out_dir)
    fig_e2e(plt.figure(figsize=(11, 6)), segs, owner_tpl, same, args.out_dir)


if __name__ == "__main__":
    main()
