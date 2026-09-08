# -*- coding: utf-8 -*-
"""D1 direction3 测试序列：el/er 能量→方向(0=中,1=左,2=右)，滞回规则同 RTL。
规则：
  中:  diff>=+TH_ON → 左; diff<=-TH_ON → 右; 否则 中
  左:  diff< TH_OFF → 中; 否则 左
  右:  diff> -TH_OFF → 中; 否则 右
TH_ON=200, TH_OFF=60。写 dir_el.mem, dir_er.mem, dir_exp.mem。"""
import os

TH_ON, TH_OFF = 200, 60
LEN = 12


def step(diff, st):
    if st == 0:                     # CENTER
        if diff >= TH_ON:
            return 1
        if diff <= -TH_ON:
            return 2
        return 0
    if st == 1:                     # LEFT
        return 0 if diff < TH_OFF else 1
    return 0 if diff > -TH_OFF else 2   # RIGHT


def main():
    seq = [  # (el, er)
        (0, 0), (300, 50), (320, 60), (90, 40), (50, 500), (60, 560),
        (100, 300), (500, 80), (700, 120), (110, 100), (80, 400), (30, 20),
    ]
    st = 0
    dirs = []
    for (el, er) in seq:
        st = step(el - er, st)
        dirs.append(st)
    print("dirs:", dirs)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "dir_el.mem"), "w") as f:
        f.write("\n".join(f"{el & 0xFFFFFF:06x}" for el, _ in seq))
    with open(os.path.join(d, "dir_er.mem"), "w") as f:
        f.write("\n".join(f"{er & 0xFFFFFF:06x}" for _, er in seq))
    with open(os.path.join(d, "dir_exp.mem"), "w") as f:
        f.write("\n".join(str(v) for v in dirs))


if __name__ == "__main__":
    main()
