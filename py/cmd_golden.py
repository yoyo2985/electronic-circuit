# -*- coding: utf-8 -*-
"""cmd_golden.py — KWS Python Golden（与 cmd_matcher/cmd_vote 一致）
功能:
  argmin L1 over templates  → cmd_id(每帧)
  sliding majority over VOTE_N  → cmd_id_out(片段)
--synthetic: 生成 4 个合成命令模板(data/commands/cmd_0..3.mem)与仿真 MFCC 帧/
   期望 id(data/cmd_frames.mem, data/cmd_ids_exp.mem)，供 ModelSim 用（无真实命令时）。
"""
import os, sys
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
DATA = os.path.join(ROOT, "data")


def read_tpl_mem(path):
    v = []
    for l in open(path):
        l = l.strip()
        if l:
            x = int(l, 16)
            v.append(x - 0x10000 if x & 0x8000 else x)
    return np.array(v, np.int64)


def frame_cmd_id(feat, tpls):
    ds = [int(np.abs(feat - t).sum()) for t in tpls]
    return int(np.argmin(ds)), min(ds)


def majority_last(seq, n):
    """模拟 cmd_vote：对末尾 n 个 id 取众数(并列取小)，输入 len 完整。"""
    out = []
    for t in range(len(seq)):
        if t < n:
            out.append(None)   # 窗口未满
        else:
            win = seq[t - n:t]
            cnt = np.bincount(win, minlength=16)
            out.append(int(np.argmax(cnt)))
    return out


def gen_synthetic(n_cmds=4, dim=13, seed=0):
    rng = np.random.default_rng(seed)
    base = rng.integers(-3000, 3000, size=(n_cmds, dim))
    cmd_dir = os.path.join(DATA, "commands")
    os.makedirs(cmd_dir, exist_ok=True)
    tpls = []
    for i in range(n_cmds):
        t = np.clip(np.round(base[i]), -32768, 32767).astype(np.int64)
        tpls.append(t)
        with open(os.path.join(cmd_dir, f"cmd_{i}.mem"), "w") as fo:
            fo.write("\n".join("%04x" % (int(v) & 0xFFFF) for v in t) + "\n")
    return tpls


def gen_test_frames(tpls, n_frames=32, dim=13, seed=1):
    """随机选模板并加噪作为 feature 帧；期望 cmd_id=模板序。写 mem 供 ModelSim。"""
    rng = np.random.default_rng(seed)
    ids = rng.integers(0, len(tpls), size=n_frames)
    feats = np.stack([tpls[j] + rng.integers(-60, 60, size=dim) for j in ids])
    feats = np.clip(feats, -32768, 32767).astype(np.int64)
    with open(os.path.join(DATA, "cmd_frames.mem"), "w") as fo:
        fo.write("\n".join("%04x" % (int(v) & 0xFFFF) for row in feats for v in row) + "\n")
    with open(os.path.join(DATA, "cmd_ids_exp.mem"), "w") as fo:
        fo.write("\n".join(str(int(v)) for v in ids) + "\n")
    return feats, ids


def main():
    import argparse
    ap=argparse.ArgumentParser()
    ap.add_argument("--names", default="0 1 2 3", help="模板序(默认合成 cmd_0..3；真实: --names stop left right forward)")
    a=ap.parse_args()
    names=a.names.split()
    tpls=[read_tpl_mem(os.path.join(DATA,"commands",f"cmd_{n}.mem")) for n in names]
    feats, ids = gen_test_frames(tpls)
    got = [frame_cmd_id(f, tpls)[0] for f in feats]
    print("loaded templates:", [f"cmd_{n}.mem" for n in names])
    print("matcher exact vs gen:", got == list(ids))
    mv = majority_last(got, 8)
    print("sample vote tail:", mv[-5:])


if __name__ == "__main__":
    main()
