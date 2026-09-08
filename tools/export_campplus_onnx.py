# -*- coding: utf-8 -*-
"""export_campplus_onnx.py — 从 ModelScope CAMPPlus 检查点导出 ONNX
用法: python tools/export_campplus_onnx.py
      [--model_dir <snapshot>] [--out py/campplus/models/campplus_emb.onnx]
输出: <out>；并做 ORT 冒烟(随机 fbank → 192-D finite, L2≈可归一)。
说明: 模型输入 fbank [B,T,80](B=1, T 动态)，输出 [B,192]。
"""
import os, sys, argparse
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))


def default_snapshot():
    cand = "C:/Users/ZhongYOYO/.cache/modelscope/models/iic--speech_campplus_sv_zh-cn_16k-common/snapshots/master"
    return cand if os.path.isdir(cand) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model_dir", default=None)
    ap.add_argument("--out", default=os.path.join(ROOT, "py", "campplus", "models", "campplus_emb.onnx"))
    a = ap.parse_args()
    mdir = a.model_dir or default_snapshot()
    if not mdir:
        sys.exit("未找到模型目录，请传 --model_dir 或先 snapshot_download")
    import torch
    from funasr import AutoModel
    am = AutoModel(model=mdir, model_revision="master", device="cpu", disable_update=True)
    net = am.model.eval()

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    dummy = torch.randn(1, 30, 80)          # [B,T,80] fbank
    torch.onnx.export(net, dummy, a.out,
                      input_names=["fbank"], output_names=["embedding"],
                      dynamic_axes={"fbank": {1: "T"}, "embedding": {0: "B"}},
                      opset_version=13)
    print("exported ->", a.out)

    import onnxruntime as ort
    so = ort.SessionOptions(); sess = ort.InferenceSession(a.out, so, providers=["CPUExecutionProvider"])
    inp = {sess.get_inputs()[0].name: dummy.numpy()}
    emb = sess.run(None, inp)[0]
    emb = emb.reshape(-1)
    print("ort dim", emb.shape[0], "finite", bool(np.isfinite(emb).all()),
          "|L2|", float(np.linalg.norm(emb)))


if __name__ == "__main__":
    main()
