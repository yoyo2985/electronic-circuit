# -*- coding: utf-8 -*-
"""B3-4a mel_bank 测试向量（整数镜像，期望精确一致）：
  mel_coef.mem    : M×NB 行，QCF 量化 Mel 系数(≤4095,hex4)
  mel_pow.mem     : NB 个功率 bin(unsigned)
  mel_exp.mem     : 期望 mel = Σ(pow*coef)>>QCF（floor）
"""
import numpy as np
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import frontend as fe

NB, M, QCF = 9, 6, 12
FS = 48000.0


def main():
    fb = fe.mel_filterbank(M, 16, FS)              # [M, NB]
    c = np.clip(np.round(fb * (1 << QCF)), 0, (1 << QCF) - 1).astype(np.int64)
    # 确定性功率向量
    powv = np.array([0, 100, 2000, 8000, 50, 4000, 9000, 300, 120], dtype=np.int64)
    mel = []
    for m in range(M):
        acc = int(np.dot(c[m], powv))
        mel.append(acc >> QCF)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "mel_coef.mem"), "w") as f:
        f.write("\n".join(f"{v:04x}" for v in c.flatten()))
    with open(os.path.join(d, "mel_pow.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08x}" for v in powv))
    with open(os.path.join(d, "mel_exp.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFFFFFFFFFF:016x}" for v in mel))
    print("mel =", mel)
    print("coef row0 =", c[0].tolist())


if __name__ == "__main__":
    main()
