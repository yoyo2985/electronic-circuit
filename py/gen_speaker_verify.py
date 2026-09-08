# -*- coding: utf-8 -*-
"""B5.3 speaker_verify 参考：模板=fe_sine_mfcc(视为 owner)，TH=5000。
零/随机帧应拒绝。写 spk_tpl.mem(13,s16) 与 spk_exp.mem(每帧 dist match)。
读取已生成的 fe_*_mfcc.mem(B4 精确) 计算 L1。"""
import os

TH = 5000
K = 13


def read_mfcc(fn):
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    return [int(l, 16) & 0xFFFF for l in open(os.path.join(d, fn))]
    # hex4 按 16bit 两补
def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def main():
    mf = {n: [s16(v) for v in read_mfcc(f"fe_{n}_mfcc.mem")] for n in ("zero", "sine", "rand")}
    tpl = mf["sine"]                       # owner 模板(用 sine 帧，后续换真实 mean)
    rows = []
    for name in ("sine", "zero", "rand"):
        d = sum(abs(a - b) for a, b in zip(mf[name], tpl))
        m = 1 if d <= TH else 0
        rows.append((d, m))
        print(name, "dist", d, "match", m)
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    with open(os.path.join(d, "spk_tpl.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in tpl))
    with open(os.path.join(d, "spk_exp.mem"), "w") as f:
        f.write("\n".join(f"{dd & 0xFFFFFFFF:08x} {m}" for dd, m in rows))


if __name__ == "__main__":
    main()
