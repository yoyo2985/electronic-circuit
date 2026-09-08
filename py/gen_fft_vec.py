# -*- coding: utf-8 -*-
"""B3-3 FFT 向量生成 + 浮点参考
  fft_in.mem           : N 个 int24 实输入(已按位倒序排好，便于 RTL 顺序载入)
  fft_exp_re/im.mem    : 期望输出 = round(real/imag of np.fft.fft(x)/N)  (int32 hex8)
  tw_re_<N>.mem, tw_im_<N>.mem : 旋转因子表 Q15(int16 hex4)，索引 m=0..N-1
RTL 逐级 >>1，理论输出≈DFT/N；比对用相对容差(低频 bin 允许一定偏差)。
"""
import numpy as np
import os
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 16
AW, FS = 24, 48000.0
MIN24, MAX24 = -(1 << 23), (1 << 23) - 1
Q15 = 1 << 15


def bit_reverse_perm(n):
    """位倒序置换：返回 rev[k]=输入顺序里的真实时域序。"""
    bits = int(np.log2(n))
    rev = [0] * n
    for i in range(n):
        rev[i] = int('{:0{bits}b}'.format(i, bits=bits)[::-1], 2)
    return rev


def main():
    t = np.arange(N) / FS
    sig = 0.3 * np.sin(2 * np.pi * (FS / N * 3) * t) + 0.2 * np.sin(2 * np.pi * (FS / N * 6) * t)
    x = np.clip(np.round(sig * (1 << 23)), MIN24, MAX24).astype(np.float64)

    # 期望（含 /N 定标，与 RTL 逐级>>1 近似）
    X = np.fft.fft(x) / N
    er = np.round(X.real).astype(np.int64)
    ei = np.round(X.imag).astype(np.int64)

    # 位倒序后的输入顺序（RTL 按 0..N-1 载入即是倒序后序列）
    perm = bit_reverse_perm(N)
    x_rev = x[perm].astype(np.int64)

    # 旋转因子 e^{-j2π m/N} * 2^15，并限幅到 signed 16 位可表示范围 [-32767,32767]
    # （cos(0)=1 量化 32768 会翻成 0x8000=-32768，必须限成 32767）
    ang = 2 * np.pi * np.arange(N) / N
    tw_r = np.clip(np.round(np.cos(ang) * Q15), -32767, 32767).astype(np.int64)
    tw_i = np.clip(np.round(-np.sin(ang) * Q15), -32767, 32767).astype(np.int64)   # 负号: 前向

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "fft_in.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in x_rev))
    with open(os.path.join(d, "fft_exp_re.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08x}" for v in er))
    with open(os.path.join(d, "fft_exp_im.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08x}" for v in ei))
    with open(os.path.join(d, "tw_re.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in tw_r))
    with open(os.path.join(d, "tw_im.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in tw_i))
    print(f"N={N} perm[:8]={perm[:8]}")
    print(f"exp_re[:6]={[int(v) for v in er[:6]]} exp_im[:6]={[int(v) for v in ei[:6]]}")


if __name__ == "__main__":
    main()
