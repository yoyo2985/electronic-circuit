# -*- coding: utf-8 -*-
"""生成 B3-1 pre_emph 的测试向量：
   sim/audio_sim/data/pre_in.mem    (输入 int24，十六进制)
   sim/audio_sim/data/pre_exp.mem   (定点参考 y=x-round(a*x[n-1])，饱和 int24)
定点参数与 rtl/pre_emph.v 必须一致：Q=14, A_FIX=15892(≈0.97*2^14)。
Python 的 >> 对负数与 Verilog 的有符号 >>> 都是“向下取整”，故可逐位一致。
"""
import numpy as np
import os

AW, Q, A_FIX = 24, 14, 15892
HALF = 1 << (Q - 1)
MIN24, MAX24 = -(1 << 23), (1 << 23) - 1
N = 700
FS = 48000.0


def preemph_fixed(x):
    out = []
    xp = 0
    for v in x:
        term = (xp * A_FIX + HALF) >> Q
        y = int(v) - term
        y = max(MIN24, min(MAX24, y))       # 饱和到 24 位有符号
        out.append(y)
        xp = int(v)
    return out


def main():
    # 前半段小幅度正弦(不饱和)，后半段大幅正弦(触发饱和)以测限幅
    t = np.arange(N) / FS
    sig = np.zeros(N)
    sig[:N // 2] = 0.20 * np.sin(2 * np.pi * 997.0 * t[:N // 2])
    sig[N // 2:] = 0.90 * np.sin(2 * np.pi * 1337.0 * t[N // 2:])
    x = np.clip(np.round(sig * (1 << 23)), MIN24, MAX24).astype(np.int64)
    exp = preemph_fixed(x.tolist())

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "pre_in.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in x.tolist()))
    with open(os.path.join(d, "pre_exp.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in exp))
    print("wrote", N, "samples ->", os.path.abspath(d))
    print("x[0..3] =", [hex(v & 0xFFFFFF) for v in x[:4]])
    print("y[0..3] =", [hex(v & 0xFFFFFF) for v in exp[:4]])


if __name__ == "__main__":
    main()
