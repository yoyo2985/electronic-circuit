# -*- coding: utf-8 -*-
"""ctl_chain 期望：decision(vad,auth,dir) 决策 → motion 映射 → (vl,vr)。
规则与 decision_fsm / motion_plan 一致。写 ct_*.mem。"""
import os

VF, VT = 80, 50
DEC = [(0, 0, 0), (1, 0, 0), (1, 0, 1), (1, 1, 0), (1, 1, 0), (1, 1, 1),
       (1, 1, 2), (0, 0, 0), (1, 1, 0), (1, 1, 2), (0, 1, 0), (1, 1, 0)]
MAP = {0: (0, 0), 1: (0, 0), 2: (VF, VF), 3: (-VT, VT), 4: (VT, -VT)}


def main():
    auth_l = 0
    vl, vr = [], []
    acts = []
    for (vad, auth, d) in DEC:
        if not vad:
            auth_l = 0
            a = 0
        else:
            if auth:
                auth_l = 1
            if not auth_l:
                a = 1
            elif d == 1:
                a = 3
            elif d == 2:
                a = 4
            else:
                a = 2
        acts.append(a)
        v = MAP[a]
        vl.append(v[0]); vr.append(v[1])

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "ct_vad.mem"), "w") as f:
        f.write("\n".join(str(a) for a, _, _ in DEC))
    with open(os.path.join(d, "ct_auth.mem"), "w") as f:
        f.write("\n".join(str(a) for _, a, _ in DEC))
    with open(os.path.join(d, "ct_dir.mem"), "w") as f:
        f.write("\n".join(str(x) for _, _, x in DEC))
    with open(os.path.join(d, "ct_vl.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFF:02x}" for v in vl))
    with open(os.path.join(d, "ct_vr.mem"), "w") as f:
        f.write("\n".join(f"{v & 0xFF:02x}" for v in vr))
    print("acts", acts, "\nvl", vl, "\nvr", vr)


if __name__ == "__main__":
    main()
