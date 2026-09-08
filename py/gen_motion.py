# -*- coding: utf-8 -*-
"""motion_plan 映射与期望：
  action: 0 IDLE/1 REJECT -> (0,0); 2 FORWARD -> (V_F,V_F);
          3 LEFT -> (-V_T,V_T); 4 RIGHT -> (V_T,-V_T)
  V_F=80, V_T=50。写 ml_act.mem + ml_vl.mem + ml_vr.mem"""
import os

VF, VT = 80, 50
MAP = {0: (0, 0), 1: (0, 0), 2: (VF, VF), 3: (-VT, VT), 4: (VT, -VT)}
seq = [0, 1, 2, 3, 4, 2, 0, 3]


def main():
    vl = [MAP[a][0] for a in seq]
    vr = [MAP[a][1] for a in seq]
    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "ml_act.mem"), "w") as f:
        f.write("\n".join(str(a) for a in seq))
    with open(os.path.join(d, "ml_vl.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFF:02x}" for v in vl))
    with open(os.path.join(d, "ml_vr.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFF:02x}" for v in vr))
    print("seq", seq, "vl", vl, "vr", vr)


if __name__ == "__main__":
    main()
