# -*- coding: utf-8 -*-
"""B5.7c utter_vote 镜像与极端序列（段级累计，替代滑动 8 帧多数决）。
RTL 镜像：段内累计匹配帧数 acc，acc>=MIN_MATCH → owner(段内粘性)；
         vad 段末 decision_valid 脉冲汇报本段判决并复位。
写 data/uv_0..uv_6.mem(每行 0/1)，data/uv_meta.mem(每行 len dec owner, hex)。"""
import os

MINM = 5
TESTS = [
    ("all_reject",  [0]*16),
    ("all_accept",  [1]*16),
    ("one_match",   [1]+[0]*15),          # 1<5 → owner0
    ("five_match",  [1]*5+[0]*11),        # =5 → owner1
    ("four_match",  [1]*4+[0]*12),        # 4<5 → owner0
    ("late_match",  [0]*11+[1]*5),        # 段尾累计到 5 → owner1
    ("short_seg",   [1]*3),               # 帧太少 → owner0
]


def simulate(seq):
    acc = sum(seq)
    return 1, 1 if acc >= MINM else 0     # (段末决策脉冲数, owner)


def main():
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    meta = []
    for i, (name, seq) in enumerate(TESTS):
        dec, owner = simulate(seq)
        with open(os.path.join(d, f"uv_{i}.mem"), "w") as f:
            f.write("\n".join(str(b) for b in seq))
        meta.append((len(seq), dec, owner))
        print(name, "len", len(seq), "dec", dec, "owner", owner)
    with open(os.path.join(d, "uv_meta.mem"), "w") as f:
        f.write("\n".join(f"{l:x} {d:x} {o:x}" for l, d, o in meta))


if __name__ == "__main__":
    main()
