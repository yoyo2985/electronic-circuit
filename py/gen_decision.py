# -*- coding: utf-8 -*-
"""decision_fsm 测试序列 → 期望动作。规则：
  !vad → action=0(IDLE), auth_l=0
  有语音：in_auth → auth_l=1
        若 auth_l==0 → action=1(REJECT)
        否则 dir:1→3(LEFT),2→4(RIGHT),0→2(FORWARD)
  写 dec_* 输入(三列)、dec_exp.mem(每窗动作)。"""
import os

LEN = 12
seq = [  # (vad, auth, dir)
    (0, 0, 0),
    (1, 0, 0),   # 陌生人说话
    (1, 0, 1),
    (1, 1, 0),   # 主人出现(center)
    (1, 1, 0),
    (1, 1, 1),   # 主人左侧
    (1, 1, 2),   # 主人右侧
    (0, 0, 0),
    (1, 1, 0),   # 重新说话仍是主人(上一段已清)
    (1, 1, 2),
    (0, 1, 0),
    (1, 1, 0),
]


def main():
    auth_l = 0
    acts = []
    for (vad, auth, d) in seq:
        if not vad:
            auth_l = 0
            acts.append(0)
        else:
            if auth:
                auth_l = 1
            if not auth_l:
                acts.append(1)      # REJECT
            elif d == 1:
                acts.append(3)
            elif d == 2:
                acts.append(4)
            else:
                acts.append(2)
    print("acts:", acts)

    d = os.path.join(os.path.dirname(__file__), "..", "sim", "audio_sim", "data")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "dec_vad.mem"), "w") as f:
        f.write("\n".join(str(v) for v, _, _ in seq))
    with open(os.path.join(d, "dec_auth.mem"), "w") as f:
        f.write("\n".join(str(a) for _, a, _ in seq))
    with open(os.path.join(d, "dec_dir.mem"), "w") as f:
        f.write("\n".join(str(x) for _, _, x in seq))
    with open(os.path.join(d, "dec_exp.mem"), "w") as f:
        f.write("\n".join(str(a) for a in acts))


if __name__ == "__main__":
    main()
