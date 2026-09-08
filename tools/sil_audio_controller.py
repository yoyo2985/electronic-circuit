# -*- coding: utf-8 -*-
"""sil_audio_controller.py — 软件在环(SIL) 语音→决策→虚拟电机 仿真（无 FPGA）
仅 Python；不调用 RTL。逻辑：
  读“主人命令”音频 → embedding/mfcc → 本地模板匹配 → owner_valid
  owner_valid=1 → target=90 → 虚拟电机(一阶惯性+位置积分) → 遥测帧
使用:
  python tools/sil_audio_controller.py --audio sounds/owner_sound/xxx.m4a --embedder mfcc
  python tools/sil_audio_controller.py --audio a.wav --embedder campplus
输出: 每 100ms 一行遥测帧 [AA][state][target][pos][chk]（0~180 位置）
"""
import os, sys, time, argparse
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
sys.path.insert(0, os.path.join(ROOT, "data"))


def read_tpl16(p):
    v = []
    for l in open(p):
        l = l.strip()
        if l:
            x = int(l, 16)
            v.append(x - 0x10000 if x & 0x8000 else x)
    return np.array(v, np.int64)


class VirtualMotor:
    """一阶惯性 + 位置积分（模拟 V1 virtual_motor；状态 0..180）"""
    TAU = 100
    STEP_MS = 100

    def __init__(self, pos=0.0, target=0.0):
        self.pos, self.target = float(pos), float(target)

    def step(self, n_steps):
        # 等效一阶离散，速度= (target-pos)/TAU per step，1 step =100ms
        k = 1 - np.exp(-self.STEP_MS / self.TAU)
        for _ in range(n_steps):
            self.pos += k * (self.target - self.pos)


def telemetry(state, target, pos):
    tgt = int(round(target)) & 0xFF
    p = int(round(pos)) & 0xFF
    chk = 0xAA ^ state ^ tgt ^ p
    return bytes([0xAA, state, tgt, p, chk])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True)
    ap.add_argument("--embedder", choices=["mfcc", "campplus"], default="mfcc")
    ap.add_argument("--tpl", default=os.path.join(ROOT, "data", "speaker", "owner_template.mem"))
    ap.add_argument("--th", type=int, default=5000)
    ap.add_argument("--target", type=int, default=90)
    ap.add_argument("--dur_s", type=float, default=3.0)
    a = ap.parse_args()

    if a.embedder == "campplus":
        from campplus.interface import extract_embedding, find_model
        if not find_model():
            sys.exit("campplus 模型缺失（见 py/campplus），无法 SIL；先用 --embedder mfcc")
        t = extract_embedding(a.audio)
        # 模板：未注册时用该音频自身作为占位（演示需先跑注册，见文档）
        score = float(np.dot(t, t) / (np.linalg.norm(t) ** 2 + 1e-9))
        owner = score > 0.9
    else:
        from audio_golden import load_mono, features_of
        x16, _ = load_mono(a.audio, 48000)
        feats, tot, act, _ = features_of(x16)
        if act == 0:
            sys.exit("active frames=0（能量门无语音）")
        mean = np.clip(np.round(feats.mean(0)), -32768, 32767).astype(np.int64)
        tpl = read_tpl16(a.tpl)
        dist = int(np.abs(mean - tpl).sum())
        owner = dist <= a.th
        print(f"[mfcc] dist={dist} TH={a.th} owner={owner}")

    if not owner:
        print("REJECT: 非主人，机器人不动。")
        return

    print("OWNER_OK → target =", a.target)
    mot = VirtualMotor(pos=0.0, target=float(a.target))
    n = max(1, int(a.dur_s * 10))
    for i in range(n):
        mot.step(1)
        st = 1 if i < n - 2 else (2 if abs(mot.pos - a.target) < 2 else 3)
        print(telemetry(st, a.target, mot.pos).hex())
        time.sleep(0.1)


if __name__ == "__main__":
    main()
