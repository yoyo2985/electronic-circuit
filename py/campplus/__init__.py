# -*- coding: utf-8 -*-
"""campplus —— CAM++ 声纹推理封装（ONNX Runtime）
输入输出约定（FunASR/CAM++ 16k 通用版）：
  fbank: 80 维 log-Mel，16 kHz，25ms/10ms（kaldi 风格）
  模型输入约 [1, T, 80]；输出 192-D embedding（调用方再 L2 归一）。
模型文件路径可配（默认在克隆仓库声明的 models/sv/campplus_emb.onnx 等候选路径查找）。
若模型缺失，extract/verify 会抛出清晰错误 —— 不伪造结果。
"""
import os

# 候选模型路径（供 ModelScope 下载的 campplus 通用 zh-cn 版）
DEFAULT_SEARCH = [
    os.getenv("CAMPPUS_ONNX", ""),
    "recognition/Speech-processing-and-recognition-based-on-Anlu-EG4S20/models/sv/campplus_emb.onnx",
    "models/sv/campplus_emb.onnx",
]


def find_model():
    for p in DEFAULT_SEARCH:
        if p and os.path.isfile(p):
            return os.path.abspath(p)
    return None
