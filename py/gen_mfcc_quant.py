# -*- coding: utf-8 -*-
"""B5.2 mfcc_quant 向量：32-bit → 16-bit，sat16(v>>>QS)。含极值。
写 mq_in.mem(int32 hex8), mq_exp0.mem(QS0), mq_exp2.mem(QS2)(int16 hex4)。"""
import os

vals = [0, 1, -1, 2, -2, 32767, -32768, 65535, -65535, 100000, -100000,
        8388608, -8388608, 2147483647, -2147483648]


def quant(v, qs):
    y = v >> qs          # 负数向下取整(与 Verilog >>> 一致)
    y = max(-32768, min(32767, y))
    return y


def main():
    e0 = [quant(v, 0) for v in vals]
    e2 = [quant(v, 2) for v in vals]
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "mq_in.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08x}" for v in vals))
    with open(os.path.join(d, "mq_exp0.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in e0))
    with open(os.path.join(d, "mq_exp2.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04x}" for v in e2))
    print("exp0", e0)
    print("exp2", e2)


if __name__ == "__main__":
    main()
