# -*- coding: utf-8 -*-
"""B3-5 DCT-II(MFCC) 向量：M 维 log-mel → K 个 DCT 系数(整数镜像，floor)。
  dct_basis.mem : M*K 行，b[k][m]=c_k*cos(pi/M*(m+0.5)k)*2^DQ 取整(int16 hex4)
  dct_in.mem    : M 个 logmel(int16 hex4)
  dct_exp.mem   : 期望 y[k]=(Σ_m x*b)>>DQ
"""
import numpy as np
import os
import sys

M, K, DQ = 6, 4, 12


def main():
    m = np.arange(M) + 0.5
    basis = np.zeros((K, M))
    for k in range(K):
        c = np.sqrt(1.0 / M) if k == 0 else np.sqrt(2.0 / M)
        basis[k] = c * np.cos(np.pi * k * m / M)
    bq = np.clip(np.round(basis * (1 << DQ)), -(1 << 15), (1 << 15) - 1).astype(np.int64)

    # 输入 log-mel(用一条上升曲线较有辨识度)
    x = np.array([1000, 1200, 2500, 3000, 1800, 900], dtype=np.int64)
    y = []
    for k in range(K):
        s = int(np.dot(bq[k], x))
        y.append(s >> DQ)
    print("y =", y)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "dct_basis.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in bq.flatten()))
    with open(os.path.join(d, "dct_in.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in x))
    with open(os.path.join(d, "dct_exp.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08x}" for v in y))


if __name__ == "__main__":
    main()
