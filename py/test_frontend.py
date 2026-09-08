# -*- coding: utf-8 -*-
"""B0 Golden Model 自检：跑 python py/test_frontend.py，全过应打印 TEST PASS。"""
import numpy as np
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import frontend as fe

fails = []


def check(name, cond, extra=""):
    if not cond:
        fails.append(name)
        print(f"[FAIL] {name} {extra}")
    else:
        print(f"[ok]   {name}")


# 1) 预加重：常值 c → y[0]=c，y[n]=c*(1-a)（DC 处增益 1-a，非全 0）
c = np.ones(64) * 0.5
y = fe.pre_emphasis(c, 0.97)
check("pre_emphasis DC 增益 (1-a)", np.isclose(y[0], 0.5) and np.allclose(y[1:], 0.5 * 0.03))

# 2) framing：形状与无缝隙拼接可重建
x = fe.sine(1000, 0.05)
fr = fe.framing(x, 512, 160)
check("framing 形状", fr.shape[1] == 512 and fr.shape[0] == 1 + (x.size - 512) // 160)

# 3) Hann 周期窗端点≈0（末点约 3.7e-5）
w = fe.hann_periodic(512)
check("hann 端点≈0", abs(w[0]) < 1e-9 and abs(w[-1]) < 1e-3)

# 4) 单音功率谱峰在正确 bin（1k/48k*512 ≈ 10.7）
x1 = fe.sine(1000, 0.2)
wp = fe.frame_prep(x1, 512, 160, preemph=0.0)
p = fe.power_spectrum(wp, 512)[0]
peak_bin = int(np.argmax(p))
check("1kHz 谱峰 bin 合理", 6 <= peak_bin <= 16, f"peak={peak_bin}")

# 5) mel 滤波器组形状/正值/行能量
fb = fe.mel_filterbank(40, 512, fe.FS)
check("melbank 形状", fb.shape == (40, 257))
check("melbank 非负且有能量", bool((fb >= 0).all()) and bool(fb.sum(axis=1).min() > 0))

# 6) 端到端 MFCC/Log-Mel 形状与有限
r = fe.compute_mfcc(fe.tone_burst([440, 1000, 3000], 0.15), preemph=0.97)
check("logmel 形状", r["logmel"].ndim == 2 and r["logmel"].shape[1] == 40)
check("mfcc 形状", r["mfcc"].shape == (r["n_frames"], 13))
check("值有限", bool(np.isfinite(r["mfcc"]).all()) and bool(np.isfinite(r["logmel"]).all()))

# 7) MFCC 确定性（重跑一致）
r2 = fe.compute_mfcc(fe.tone_burst([440, 1000, 3000], 0.15), preemph=0.97)
check("mfcc 确定性", np.allclose(r["mfcc"], r2["mfcc"]))

# 8) pcm24 负端往返：-2^23(24 位补码) → -1.0
neg = fe.pcm24_to_float(np.int32(-2 ** 23))
check("pcm24 负端 ≈ -1", np.isclose(neg, -1.0), f"{neg}")

print()
if fails:
    print(f"TEST FAIL : {len(fails)} check(s): {fails}")
    sys.exit(1)
print("TEST PASS : B0 frontend golden model checks all green")
