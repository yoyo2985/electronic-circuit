# -*- coding: utf-8 -*-
"""B3-2 front_wind 测试向量：
  hann_<N>.mem   : Hann 周期窗 Q15 量化(16bit 无符号存 hex4)
  front_in.mem   : 帧数×N 的 int24 正弦输入
  front_exp.mem  : 期望加窗输出(逐点 Q15 乘、四舍五入、饱和 int24，帧序拼接)
定点算法须与 front_wind.v 一致：(sample*win + 2^14) >> 15 (向下取整) 后饱和。
"""
import numpy as np
import os
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 64
FRAMES = 3
AW, FS = 24, 48000.0
MIN24, MAX24 = -(1 << 23), (1 << 23) - 1
Q15 = 1 << 15


def hann_q15(n):
    m = np.arange(n)
    h = 0.5 - 0.5 * np.cos(2 * np.pi * m / n)
    return np.round(h * Q15).astype(np.int64)   # 0..~32767


def windowed_frame(xf, win):
    out = []
    for v, w in zip(xf, win):
        prod = int(v) * int(w)
        y = (prod + (1 << 14)) >> 15
        y = max(MIN24, min(MAX24, y))
        out.append(y)
    return out


def main():
    total = FRAMES * N
    t = np.arange(total) / FS
    sig = 0.3 * np.sin(2 * np.pi * 997.0 * t) + 0.15 * np.sin(2 * np.pi * 3111.0 * t)
    x = np.clip(np.round(sig * (1 << 23)), MIN24, MAX24).astype(np.int64)

    win = hann_q15(N)
    exp = []
    for f in range(FRAMES):
        exp += windowed_frame(x[f * N:(f + 1) * N], win)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"hann_{N}.mem"), "w") as fh:
        fh.write("\n".join(f"{v & 0xFFFF:04x}" for v in win))
    with open(os.path.join(d, "front_in.mem"), "w") as fh:
        fh.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in x))
    with open(os.path.join(d, "front_exp.mem"), "w") as fh:
        fh.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in exp))
    print(f"N={N} frames={FRAMES} total={total}  win[0..2]={[int(w) for w in win[:3]]}")


if __name__ == "__main__":
    main()
