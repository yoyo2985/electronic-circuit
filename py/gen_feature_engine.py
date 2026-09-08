# -*- coding: utf-8 -*-
"""B4 feature_engine Golden：与 RTL 完全一致的整数镜像链(逐级 floor)，
生成 3 组(全0/1kHz/定种子随机) PCM + 参考 MFCC(K=13)。
各级镜像与已验证积木/数据文件一致(hann_64/tw/mel_coef/log2_lut/dct_basis)。
"""
import numpy as np
import os
import math
import sys
sys.path.insert(0, os.path.dirname(__file__))
import frontend as fe

AW, N, NB, M, K, PS = 24, 64, 33, 20, 13, 22
FS = 48000.0
MIN24, MAX24 = -(1 << 23), (1 << 23) - 1
Q15 = 1 << 15


def hann_q15(n):
    m = np.arange(n)
    return np.round((0.5 - 0.5 * np.cos(2 * np.pi * m / n)) * Q15).astype(np.int64).tolist()


def pre_emph(x):
    out = []
    xp = 0
    for v in x:
        term = (xp * 15892 + (1 << 13)) >> 14
        out.append(int(v) - term)
        xp = int(v)
    return out


def window_frame(x, win):
    o = []
    for v, w in zip(x, win):
        o.append(max(MIN24, min(MAX24, ((int(v) * int(w) + (1 << 14)) >> 15))))
    return o


def fft_fixed(x):
    n = len(x)
    bits = int(math.log2(n))
    rev = [int(format(i, '0%db' % bits)[::-1], 2) for i in range(n)]
    arr = [int(x[rev[i]]) for i in range(n)]
    im = [0] * n
    ang = 2 * math.pi * np.arange(n) / n
    twr = np.clip(np.round(np.cos(ang) * Q15), -32767, 32767).astype(np.int64)
    twi = np.clip(np.round(-np.sin(ang) * Q15), -32767, 32767).astype(np.int64)
    for stage in range(bits):
        half = 1 << stage
        for q in range(n // 2):
            j = q & (half - 1)
            a = (q >> stage) << (stage + 1)
            a += j
            b = a + half
            ti = j << (bits - 1 - stage)
            wr, wi = int(twr[ti]), int(twi[ti])
            br, bi = arr[b], im[b]
            tr = (br * wr - bi * wi) >> 15
            ti2 = (br * wi + bi * wr) >> 15
            ar, ai = arr[a], im[a]
            arr[a] = (ar + tr) >> 1
            im[a] = (ai + ti2) >> 1
            arr[b] = (ar - tr) >> 1
            im[b] = (ai - ti2) >> 1
    return arr, im


def mel_quant():
    fb = fe.mel_filterbank(M, N, FS)  # [20,33]
    return np.clip(np.round(fb * (1 << 12)), 0, 4095).astype(np.int64)


def log_lut():
    return [int(round(math.log2(1 + k / 64) * 256)) for k in range(64)]


def ilog2(x, lut):
    if x <= 0:
        return 0
    e = x.bit_length() - 1
    idx = ((x - (1 << e)) << 6) >> e
    return (e << 8) + lut[idx]


def dct_basis_quant():
    m = np.arange(M) + 0.5
    b = np.zeros((K, M))
    for k in range(K):
        c = math.sqrt(1.0 / M) if k == 0 else math.sqrt(2.0 / M)
        b[k] = c * np.cos(np.pi * k * m / M)
    return np.clip(np.round(b * (1 << 12)), -32767, 32767).astype(np.int64)


def chain_mfcc(x):
    pe = pre_emph(x)
    w = window_frame(pe, hann_q15(N))
    re, im = fft_fixed(w)
    powr = [((re[k] * re[k] + im[k] * im[k]) >> PS) for k in range(NB)]
    c = mel_quant()
    mel = [(int(np.dot(c[m], powr))) >> 12 for m in range(M)]
    lut = log_lut()
    logm = [ilog2(v, lut) for v in mel]
    bq = dct_basis_quant()
    mf = [0] * K
    for k in range(K):
        s = 0
        for mm in range(M):
            s += logm[mm] * int(bq[k][mm])
        mf[k] = s >> 12
    return mf


def gen_test(name, x):
    x = np.clip(np.round(x * (1 << 23)), MIN24, MAX24).astype(np.int64)
    mf = chain_mfcc(x.tolist())
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    with open(os.path.join(d, f"fe_{name}.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFF:06x}" for v in x))
    with open(os.path.join(d, f"fe_{name}_mfcc.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in mf))
    return mf


def main():
    t = np.arange(N) / FS
    tests = {}
    tests["zero"] = np.zeros(N)
    tests["sine"] = 0.30 * np.sin(2 * np.pi * (FS / N * 5) * t)
    rng = np.random.default_rng(42)
    tests["rand"] = 0.25 * rng.standard_normal(N)
    for name, x in tests.items():
        mf = gen_test(name, x)
        print(name, "mfcc[:5]", mf[:5])


if __name__ == "__main__":
    main()
