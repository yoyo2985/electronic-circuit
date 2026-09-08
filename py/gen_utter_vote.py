# -*- coding: utf-8 -*-
"""B5.7 utter_vote 镜像与极端序列。VOTE_N=8 MIN=5。
RTL 镜像：hist newest-first；removed=oldest；acc'=acc-removed+new；
         frames_seen>=VOTE_N 时才判决。
写 data/uv_0..uv_6.mem(每行 bit hex)，data/uv_meta.mem(每行 len dec owner, hex)。"""
import os
from collections import deque

N, MINM = 8, 5
TESTS = [
    ("all_reject", [0]*16),
    ("all_accept", [1]*16),
    ("1acc15rej", [1]+[0]*15),
    ("8acc8rej",  [1]*8+[0]*8),
    ("9acc7rej_window", [0]*5+[1]*9+[0]*2),   # 窗口6+ → owner1
    ("9acc7rej_far",    [1]*9+[0]*7),          # 末窗口=0 → owner0
    ("insufficient",    [0]*3),
]


def simulate(seq):
    hist = deque([0] * N, maxlen=N)   # newest first? appendleft
    acc = 0
    frames = 0
    owner = 0
    dec = 0
    for m in seq:
        removed = hist[-1]
        hist.appendleft(m)
        hist.pop()
        acc = acc - removed + m
        if frames >= N:
            owner = 1 if acc >= MINM else 0
            dec += 1
        frames += 1
    return dec, owner


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
