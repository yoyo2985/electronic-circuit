# -*- coding: utf-8 -*-
"""B0 Python 前端 Golden Model（FPGA 实时语音前端在 PC 上的参考实现）

目的：
  - 作为 B3(FPGA MFCC/Log-Mel RTL) 的“逐帧比对基准”与参数导出源
    （系数 → .mem/.coe；用定点数复算后与 numpy 结果比 RMS/max err）。
  - 所有长度/阶数都用显式参数，方便一对一搬到 RTL。
约定：
  - 输入为浮点，范围约 [-1,1]（从 24bit PCM / 2^23 归一化）。
  - fs 默认 48000（ES8388 I2S 48k）。
"""
import numpy as np

FS = 48000

# ----------------------------------------------------------------------
# 0. 测试/输入 stimulus
# ----------------------------------------------------------------------
def sine(freq, dur_s, fs=FS, amp=0.5, phase=0.0):
    n = int(round(fs * dur_s))
    t = np.arange(n) / fs
    return amp * np.sin(2 * np.pi * freq * t + phase)


def tone_burst(freqs, dur_s, fs=FS, amp=0.5, gap_s=0.1):
    """一串单音（便于看频谱/能量分段）。"""
    segs = [sine(f, dur_s, fs, amp) for f in freqs]
    gap = np.zeros(int(fs * gap_s))
    out = []
    for i, s in enumerate(segs):
        if i:
            out.append(gap.copy())
        out.append(s)
    return np.concatenate(out)


def pcm24_to_float(x_int24):
    """int32 里低 24 位的有符号采样 → [-1,1] 浮点。"""
    x = np.asarray(x_int24, dtype=np.int64)
    x = (x << 8) >> 8            # 符号扩展到 64 位
    return (x / 2.0 ** 23).astype(np.float64)


# ----------------------------------------------------------------------
# 1. 预加重 / 去直流 / 分帧 / 加窗
# ----------------------------------------------------------------------
def pre_emphasis(x, a=0.97):
    """一阶高通：y[n]=x[n]-a*x[n-1]。RTL 用定点 y[n]=x[n]-(a>>?)x[n-1]。"""
    x = np.asarray(x, dtype=np.float64)
    y = np.empty_like(x)
    y[0] = x[0]
    y[1:] = x[1:] - a * x[:-1]
    return y


def dc_block(x, a=0.999):
    """一阶直流阻塞 y[n]=x[n]-x[n-1]+a*y[n-1]（选配）。"""
    x = np.asarray(x, dtype=np.float64)
    y = np.empty_like(x)
    prev = 0.0
    xm1 = 0.0
    for n in range(x.size):
        y[n] = x[n] - xm1 + a * prev
        xm1, prev = x[n], y[n]
    return y


def framing(x, frame_len, hop):
    """把 1D 信号切成 [帧数, frame_len]。短于 1 帧则报错。"""
    n = 1 + (int(x.size) - frame_len) // hop
    if n < 1 or x.size < frame_len:
        raise ValueError(f"信号太短: {x.size} < frame_len {frame_len}")
    idx = np.arange(frame_len)[None, :] + hop * np.arange(n)[:, None]
    return x[idx]


def hann_periodic(n):
    """周期 Hann（常用 STFT 约定）：0.5-0.5cos(2πm/N), m=0..N-1。"""
    m = np.arange(n)
    return 0.5 - 0.5 * np.cos(2 * np.pi * m / n)


def frame_prep(x, frame_len, hop, preemph=0.0, win=None):
    """预加重→分帧→加窗，返回 [帧数, frame_len]。win=None 时用 Hann。"""
    if preemph:
        x = pre_emphasis(x, preemph)
    fr = framing(x, frame_len, hop)
    if win is None:
        win = hann_periodic(frame_len)
    return fr * win


# ----------------------------------------------------------------------
# 2. Mel 滤波器组 / Log-Mel / MFCC
# ----------------------------------------------------------------------
def hz_to_mel(f):
    return 2595.0 * np.log10(1.0 + np.asarray(f) / 700.0)


def mel_to_hz(m):
    return 700.0 * (10.0 ** (np.asarray(m) / 2595.0) - 1.0)


def mel_filterbank(n_mels, n_fft, fs=FS, fmin=0.0, fmax=None):
    """三角 Mel 滤波器组 → [n_mels, n_fft//2+1]。RTL 导出为系数 ROM。"""
    if fmax is None:
        fmax = fs / 2.0
    n_freqs = n_fft // 2 + 1
    fft_freqs = np.linspace(0.0, fs / 2.0, n_freqs)
    mel_pts = np.linspace(hz_to_mel(fmin), hz_to_mel(fmax), n_mels + 2)
    hz_pts = mel_to_hz(mel_pts)
    pts = np.floor((n_fft + 1) * hz_pts / fs).astype(int)
    pts = np.clip(pts, 0, n_freqs - 1)
    fb = np.zeros((n_mels, n_freqs))
    for m in range(n_mels):
        l, c, r = pts[m], pts[m + 1], pts[m + 2]
        for f in range(l, c + 1):
            if f < n_freqs and c > l:
                fb[m, f] = (f - l) / (c - l)
        for f in range(c, r + 1):
            if f < n_freqs and r > c:
                fb[m, f] = (r - f) / (r - c)
    return fb


def power_spectrum(framed, n_fft):
    """已加窗帧 [F,L] → 功率谱 [F, n_fft//2+1]（含 DC 与 Nyquist 正频）。"""
    spec = np.fft.rfft(framed, n=n_fft, axis=-1)
    return (spec.real ** 2 + spec.imag ** 2)


def log_mel(power, fb, eps=1e-10):
    """功率谱经 mel 组 → log。RTL 用定点近似 log。"""
    mel = fb @ power.T            # [n_mels, F]
    return np.log(mel.T + eps)    # [F, n_mels]


def dct_ii_ortho(y, n_out):
    """逐帧 DCT-II 正交归一（HTK 式），输入 [F,L] → [F,n_out]。"""
    f, l = y.shape
    k = np.arange(n_out)[:, None]     # [n_out,1]
    n = np.arange(l)[None, :]         # [1,l]
    d = np.cos(np.pi / l * (n + 0.5) * k)   # [n_out,l]
    c = np.sqrt(2.0 / l) * np.ones(n_out)
    c[0] = np.sqrt(1.0 / l)
    return (c[:, None] * (d @ y.T)).T       # [F, n_out]


def compute_mfcc(x, frame_len=512, hop=160, n_fft=512, n_mels=40,
                 n_mfcc=13, preemph=0.97, fmax=None):
    """端到端：PCM→MFCC。返回 dict(mfcc, logmel, power)。"""
    w = frame_prep(x, frame_len, hop, preemph=preemph)
    p = power_spectrum(w, n_fft)
    fb = mel_filterbank(n_mels, n_fft, FS, fmax=fmax)
    lm = log_mel(p, fb)
    mf = dct_ii_ortho(lm, n_mfcc)
    return dict(mfcc=mf, logmel=lm, power=p, melbank=fb, n_frames=w.shape[0])


if __name__ == "__main__":
    # 快速自检：单音 MFCC 形状
    x = sine(1000, 0.2)
    r = compute_mfcc(x)
    print("frames", r["n_frames"], "mfcc", r["mfcc"].shape, "logmel", r["logmel"].shape)
