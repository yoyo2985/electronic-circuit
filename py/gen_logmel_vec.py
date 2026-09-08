# -*- coding: utf-8 -*-
"""logmel_chain 期望：先算 mel（同 mel_bank），再对每个 mel 做定点 log2（同 log2_lut），
写 logmel_exp.mem（M 个）。读已有 data/mel_exp.mem 复用精确 mel 值。"""
import os

FW, BW = 8, 6
k = [i / (1 << BW) for i in range(1 << BW)]
import math
lut = [int(round(math.log2(1 + ki) * (1 << FW))) for ki in k]


def ilog2(x):
    if x <= 0:
        return 0
    e = x.bit_length() - 1
    xlo = x - (1 << e)
    idx = (xlo << BW) >> e
    return (e << FW) + lut[idx]


def main():
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    mels = [int(l, 16) for l in open(os.path.join(d, "mel_exp.mem"))]
    logs = [ilog2(m) for m in mels]
    with open(os.path.join(d, "logmel_exp.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in logs))
    print("mel", mels, "-> log", logs)


if __name__ == "__main__":
    main()
