# -*- coding: utf-8 -*-
"""B3-4b 定点 log2 LUT 测试向量：
  log2_lut.mem : BW 项，log2(1+k/2^BW)*2^FW 取整(hex4)
  log_in.mem   : 待求 mel/能量(48bit,hex12)
  log_exp.mem  : 期望 = (e<<FW)+LUT[idx]，其中 e=floor(log2 x)，
                 idx = ((x-2^e)<<BW)>>e（x=0→0）。与 rtl/log2_lut.v 完全一致。
"""
import numpy as np
import os

XW, FW, BW = 48, 8, 6


def ilog2(x):
    if x <= 0:
        return 0
    e = x.bit_length() - 1
    xlo = x - (1 << e)
    idx = (xlo << BW) >> e
    lut = lut_vals[idx]
    return (e << FW) + lut


def build_lut():
    k = np.arange(BW ** 2) if False else np.arange(1 << BW)
    vals = np.round(np.log2(1 + k / (1 << BW)) * (1 << FW)).astype(np.int64)
    return vals


lut_vals = build_lut()

# 输入：含 0、边界、小/大值
xs = [0, 1, 2, 3, 4, 7, 63, 64, 127, 128, 255, 1023, 4095, 65535,
      12799, (1 << 24) + 12345, (1 << 40) + 777]

exp = [ilog2(x) for x in xs]
print("xs[:6]", xs[:6], "exp[:6]", exp[:6])


def main():
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "log2_lut.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in lut_vals))
    with open(os.path.join(d, "log_in.mem"), "w") as f:
        f.write("\n".join(f"{v & ((1 << XW) - 1):012x}" for v in xs))
    with open(os.path.join(d, "log_exp.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in exp))
    print("wrote", len(xs), "values")


if __name__ == "__main__":
    main()
