# -*- coding: utf-8 -*-
"""C2-lite 模板距离(L1)测试向量：
  vtmpl.mem      : DIM 维主人模板(int16 hex4)
  vvec.mem       : 测试向量(2 组，各 DIM 维)
  vtmpl_exp.mem  : 期望距离 = Σ|x-t|(int32 hex8) 与 match(1/0)，每组一行两列已合并
"""
import os

DIM, TH = 4, 500


def main():
    tpl = [-1000, 2000, -800, 300]
    # 组1：接近 → 距离小(match)；组2：远 → 不 match
    vecs = [
        [-900, 1900, -700, 200],
        [4000, -3000, 9000, -2000],
    ]
    lines_dist, lines_match = [], []
    for v in vecs:
        d = sum(abs(a - b) for a, b in zip(v, tpl))
        lines_dist.append(f"{d & 0xFFFFFFFF:08x}")
        lines_match.append(f"{1 if d <= TH else 0}")
    print("dist/match:", lines_dist, lines_match)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "vtmpl.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in tpl))
    with open(os.path.join(d, "vvec.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for vv in vecs for v in vv))
    with open(os.path.join(d, "vdist_exp.mem"), "w") as f:
        f.write("\n".join(lines_dist))
    with open(os.path.join(d, "vmatch_exp.mem"), "w") as f:
        f.write("\n".join(lines_match))


if __name__ == "__main__":
    main()
