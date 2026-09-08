# -*- coding: utf-8 -*-
"""audio_golden.py — 与 FPGA feature_engine(B4) 逐位一致的向量化特征提取
  解码(m4a→48k mono int16) + 能量门(离线临时 VAD) + 13-D int16 MFCC(向量化整数镜像)。
  与 py/gen_feature_engine.py 的标量镜像逐帧逐位一致(self-check in __main__)。
"""
import os, sys
import numpy as np
import av

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from frontend import mel_filterbank

AW, N, NB, M, K, PS = 24, 64, 33, 20, 13, 22
Q15 = 1 << 15
MIN24, MAX24 = -(1 << 23), (1 << 23) - 1

# ---- 常量表（与 B4 数据文件一致，避免每次重算） ----
_m = np.arange(N)
_HANN = np.round((0.5 - 0.5 * np.cos(2 * np.pi * _m / N)) * Q15).astype(np.int64)
_ang = 2 * np.pi * np.arange(N) / N
_TWR = np.clip(np.round(np.cos(_ang) * Q15), -32767, 32767).astype(np.int64)
_TWI = np.clip(np.round(-np.sin(_ang) * Q15), -32767, 32767).astype(np.int64)
_C = np.clip(np.round(mel_filterbank(M, N, 48000.0) * (1 << 12)), 0, 4095).astype(np.int64)
_mm = np.arange(M) + 0.5
_b = np.zeros((K, M))
for k in range(K):
    cc = np.sqrt(1.0 / M) if k == 0 else np.sqrt(2.0 / M)
    _b[k] = cc * np.cos(np.pi * k * _mm / M)
_BQ = np.clip(np.round(_b * (1 << 12)), -32767, 32767).astype(np.int64)
_lk = np.arange(64)
_LOG_LUT = np.round(np.log2(1 + _lk / 64.0) * 256).astype(np.int64)
_bits = int(np.log2(N))
_rev = np.array([int(format(i, '0%db' % _bits)[::-1], 2) for i in range(N)])
_pre_stages = []
for stage in range(_bits):
    half = 1 << stage
    j = np.arange(N // 2)
    idxa = ((j >> stage) << (stage + 1)) + (j & (half - 1))
    idxb = idxa + half
    ti = (j & (half - 1)) << (_bits - 1 - stage)
    _pre_stages.append((idxa, idxb, ti))


def load_mono(path, sr=48000):
    """解码为 48k、int16，返回 L 声道(默认 channel=L；保留 R 由调用方从 stereo 取)。"""
    c = av.open(path)
    res = av.AudioResampler(format="s16", layout="stereo", rate=sr)
    bufL, bufR = [], []
    for frame in c.decode(audio=0):
        for f in res.resample(frame):
            arr = f.to_ndarray()          # (ch, n) int16；若解码为单声道则 ch=1
            if arr.ndim == 1:
                bufL.append(arr.astype(np.int16)); bufR.append(arr.astype(np.int16))
            elif arr.shape[0] >= 2:
                bufL.append(arr[0].astype(np.int16))
                bufR.append(arr[1].astype(np.int16))
            else:
                bufL.append(arr[0].astype(np.int16)); bufR.append(arr[0].astype(np.int16))
    c.close()
    return (np.concatenate(bufL) if bufL else np.zeros(0, np.int16),
            np.concatenate(bufR) if bufR else np.zeros(0, np.int16))


def frame_energy(x16):
    """非重叠 64 采样帧能量(int16 域 RMS)。返回 (frames, rms per frame)."""
    n = (x16.size // N) * N
    fr = x16[:n].astype(np.int64).reshape(-1, N)
    rms = np.sqrt((fr.astype(np.float64) ** 2).mean(axis=1))
    return fr, rms


def active_mask(rms, per=None, floor=60.0, frac=0.08):
    """离线临时能量 VAD：rms >= max(floor, frac*max_rms)。"""
    peak = float(np.max(rms)) if rms.size else 0.0
    return rms >= max(floor, frac * peak)


def _preemph_batch(fr):
    """逐帧独立预加重(与 FPGA 帧级一致)：y[:,0]=x[:,0], y[:,t]=x[:,t]-a x[:,t-1]"""
    a_fix = 15892
    y = fr.astype(np.int64).copy()
    term = (fr[:, :-1] * a_fix + (1 << 13)) >> 14
    y[:, 1:] = fr[:, 1:] - term
    return y


def _window_batch(pe):
    return np.clip((pe * _HANN[None, :] + (1 << 14)) >> 15, MIN24, MAX24)


def _fft_batch(w):
    F = w.shape[0]
    re = w[:, _rev].astype(np.int64).copy()   # 位倒序载入
    im = np.zeros((F, N), dtype=np.int64)
    for stage in range(_bits):
        idxa, idxb, ti = _pre_stages[stage]
        wr = _TWR[ti]
        wi = _TWI[ti]
        ra = re[:, idxa].copy(); ia = im[:, idxa].copy()
        rb = re[:, idxb].copy(); ib = im[:, idxb].copy()
        tr = (rb * wr[None, :] - ib * wi[None, :]) >> 15
        ti2 = (rb * wi[None, :] + ib * wr[None, :]) >> 15
        re[:, idxa] = (ra + tr) >> 1
        im[:, idxa] = (ia + ti2) >> 1
        re[:, idxb] = (ra - tr) >> 1
        im[:, idxb] = (ia - ti2) >> 1
    return re, im


def _mel_batch(re, im):
    powr = (re[:, :NB] * re[:, :NB] + im[:, :NB] * im[:, :NB]) >> PS
    mel = (powr @ _C.T) >> 12
    return mel


def _log_batch(mel):
    x = np.maximum(mel, 0).astype(np.int64)
    out = np.zeros_like(x)
    mask = x > 0
    if mask.any():
        xx = x[mask]
        e = np.frexp(xx.astype(np.float64))[1].astype(np.int64) - 1   # floor(log2)
        idx = ((xx - (1 << e)) << 6) >> e
        out[mask] = (e << 8) + _LOG_LUT[idx]
    return out


def _dct_batch(logm):
    c = (logm.astype(np.int64) @ _BQ.T) >> 12
    return c


def feat16(dct):
    """转 16bit(与 engine feature_data 一致：截断低 16 位并符号化)。"""
    v = dct & 0xFFFF
    v = np.where(v & 0x8000, v - 0x10000, v)
    return v.astype(np.int16)


def features_of(x16):
    """整段→ (active int16 features [F,13], total, active, rms).
    帧=非重叠64；输入 int16，先扩到 int24 尺度(×2^8) 与 FPGA 24-bit 一致。"""
    x24 = x16.astype(np.int64) << 8
    fr16, rms = frame_energy(x16)
    if fr16.shape[0] == 0:
        return np.zeros((0, K), np.int16), 0, 0, rms
    mask = active_mask(rms)
    act = x24[: (fr16.shape[0] * N)].reshape(-1, N)[mask]
    pe = _preemph_batch(act)
    w = _window_batch(pe)
    re, im = _fft_batch(w)
    mel = _mel_batch(re, im)
    logm = _log_batch(mel)
    dct = _dct_batch(logm)
    return feat16(dct), fr16.shape[0], int(mask.sum()), rms


if __name__ == "__main__":
    # 自检：标量链(gen_feature_engine) vs 向量化, 随机帧逐位
    import gen_feature_engine as ge
    rng = np.random.default_rng(7)
    X = np.clip(np.round(0.25 * rng.standard_normal((8, N)) * (1 << 23)), MIN24, MAX24).astype(np.int64)
    ref = np.array([np.array(ge.chain_mfcc(X[r].tolist()), dtype=np.int64) for r in range(8)])
    Y = _preemph_batch(X)
    Wv = _window_batch(Y)
    re, im = _fft_batch(Wv)
    mel = _mel_batch(re, im)
    lm = _log_batch(mel)
    dt = _dct_batch(lm)
    print("self-check max abs diff (dct):", int(np.abs(dt.astype(np.int64) - ref).max()))
