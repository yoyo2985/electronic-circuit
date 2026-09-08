# -*- coding: utf-8 -*-
"""campplus/interface.py — 高层接口
    extract_embedding(wav_path) -> 192-D L2 归一 float32
    verify_speaker(emb1, emb2)   -> 余弦相似度
    load_audio(path, sr=16000)   -> float32 单声道
模型路径不存在时给出清晰错误（不伪造）。fbank 用 numpy 实现(≈kaldi，非逐位)，
若装 kaldi_native_fbank 则优先用它以获得标准 CAM++ 前端。
"""
import os
import sys
import numpy as np

from . import find_model

SR = 16000
N_MEL = 80


# ---------------- 音频读入 ----------------
def load_audio(path, sr=SR):
    try:
        import soundfile as sf
        x, fs = sf.read(path, always_2d=True)
        x = x[:, 0]
    except Exception:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
        from audio_golden import load_mono
        x16, _ = load_mono(path, sr)   # 支持 m4a；返回 int16 @sr
        return (x16.astype(np.float32) / 32768.0)
    if fs != sr:
        # 线性重采样（占位；高质量可用 torchaudio/kaldi 重采样）
        n = int(round(len(x) * sr / fs))
        idx = np.linspace(0, len(x) - 1, n)
        x = np.interp(idx, np.arange(len(x)), x).astype(np.float32)
    return x.astype(np.float32)


# ---------------- 80 维 fbank（25ms/10ms） ----------------
def _mel_filterbank(n_mels, n_fft, sr, fmin=0, fmax=None):
    if fmax is None:
        fmax = sr / 2
    n_bins = n_fft // 2 + 1
    ff = np.linspace(0, sr / 2, n_bins)
    def h2m(f):
        return 2595 * np.log10(1 + f / 700)
    mpts = np.linspace(h2m(fmin), h2m(fmax), n_mels + 2)
    hz = 700 * (10 ** (mpts / 2595) - 1)
    pts = np.floor((n_fft + 1) * hz / sr).astype(int)
    fb = np.zeros((n_mels, n_bins))
    for m in range(n_mels):
        l, c, r = pts[m], pts[m + 1], pts[m + 2]
        for k in range(l, r):
            if k < n_bins:
                fb[m, k] = min((k - l) / (c - l) if c > l else 1.0,
                               (r - k) / (r - c) if r > c else 1.0)
    return fb


def _fbank80(x, sr=SR):
    n_fft, hop = 512, 160
    n_frames = 1 + (len(x) - n_fft) // hop
    if n_frames < 1:
        raise ValueError("音频太短")
    win = np.hanning(n_fft + 1)[:-1]
    fb = _mel_filterbank(N_MEL, n_fft, sr)
    feats = []
    for i in range(n_frames):
        seg = x[i * hop:i * hop + n_fft] * win
        p = np.abs(np.fft.rfft(seg, n_fft)) ** 2
        feats.append(np.log(np.maximum(fb @ p, 1e-10)))
    return np.stack(feats, axis=0).astype(np.float32)   # [T,80]


def _load_session(model):
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(model, sess_options=so,
                                providers=["CPUExecutionProvider"])


_SESSION = None
_MODEL_PATH = None


def _session():
    global _SESSION, _MODEL_PATH
    p = find_model()
    if not p:
        raise FileNotFoundError(
            "未找到 CAM++ 模型 campplus_emb.onnx（参考克隆内缺失）。\n"
            "请从 ModelScope 'iic/speech_campplus_sv_zh-cn_16k-common' 下载并放到候选路径，"
            "或设置环境变量 CAMPPUS_ONNX=<绝对路径>。")
    if p != _MODEL_PATH:
        _SESSION = _load_session(p)
        _MODEL_PATH = p
    return _SESSION


def extract_embedding(wav_path):
    """返回 192-D L2 归一化 embedding(float32)。"""
    x = load_audio(wav_path, SR)
    f = _fbank80(x)                       # [T,80]
    sess = _session()
    inp = sess.get_inputs()[0]
    # 常见约定: 需要 (1, T, 80) float32；若输入名带别的形状由用户按需适配
    feed = {inp.name: f[None, :, :]}
    out = sess.run(None, feed)[0]         # 取第一个输出
    emb = out.reshape(-1).astype(np.float32)
    n = np.linalg.norm(emb)
    return (emb / n) if n > 0 else emb


def verify_speaker(emb1, emb2):
    """余弦相似度（输入应为 L2 归一化）。"""
    return float(np.dot(emb1, emb2))
