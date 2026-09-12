# -*- coding: utf-8 -*-
"""voice_replay_eval.py — 真实手机录音的三层 Level-1(PC offline)评估
  声纹:  owner_sound 15 条 (leave-one-out 真)  vs  stranger1/2 (假)
        - 帧级 L1 距离分布 (与 FPGA speaker_verify/vtmpl 同口径: 13×int16 L1)
        - 录音级(整段帧均值→L1) 距离分布 (更强的聚合判别, 记为 utterance-mean)
        - 输出 owner_template.mem (全部 owner 帧均值 int16, 与 FPGA 读取格式一致)
  命令:  owner_sound/commands/{forward,left,right,stop} 各 1 条, 内含多次重复念词,
        按帧能量把每文件切成若干 "utterance" 实例;
        对每个命令模板 = 该命令除被测实例外全部实例帧的均值 (leave-utterance-out),
        逐实例 argmin(4 命令 L1) 分类 → 混淆矩阵/accuracy(减小模板=测试泄漏)。
  输出: reports/voice_replay/*.csv + .mem 模板
  说明: 模板格式 13×hex4 int16, 与 RTL vtmpl 读取一致; 只写 data/ 下模板, 不改 sounds/。
"""
import os, sys, csv
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
import audio_golden as ag

OUT = os.path.join(ROOT, "reports", "voice_replay")
os.makedirs(OUT, exist_ok=True)
DATA_FEAT = os.path.join(ROOT, "data", "speaker_features")

K = 13
Q15 = 1 << 15


def full_features(x16):
    """所有帧(含静音)的 int16 13-D MFCC [T,13]，与 active 帧同链同定标。"""
    n = (x16.size // ag.N) * ag.N
    if n == 0:
        return np.zeros((0, K), np.int16)
    x24 = x16[:n].astype(np.int64) << 8
    fr = x24.reshape(-1, ag.N)
    pe = ag._preemph_batch(fr)
    w = ag._window_batch(pe)
    re, im = ag._fft_batch(w)
    mel = ag._mel_batch(re, im)
    logm = ag._log_batch(mel)
    d = ag._dct_batch(logm)
    return ag.feat16(d)


def run_mask(rms, per=None, floor=60.0, frac=0.08, min_gap=8, min_run=20):
    """能量门 → 连续活动帧 run(词实例)。返回 list[(start,end) 帧区间]。"""
    mask = rms >= max(floor, frac * float(np.max(rms)) if rms.size else 0.0)
    runs = []
    i = 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j < len(mask) and mask[j]:
                j += 1
            # 小间隙合并(允许词内 8 帧低能量)在此不处理; 直接收 run
            if (j - i) >= min_run:
                runs.append((i, j))
            i = j
        else:
            i += 1
    return runs


def l1(a, b):
    return int(np.abs(a.astype(np.int64) - b.astype(np.int64)).sum())


# ---------------- 载入 owner/stranger 帧 ----------------
def load_feat(dirn):
    d = os.path.join(DATA_FEAT, dirn)
    out = {}
    for f in sorted(os.listdir(d)):
        if f.endswith(".npz"):
            out[f] = np.load(os.path.join(d, f))["features"].astype(np.int64)
    return out

owner_files = load_feat("owner_sound")          # 15
str1 = load_feat("stranger1")                   # 14
str2 = load_feat("stranger2")                   # 10

print("owner files:", len(owner_files), "stranger1:", len(str1), "stranger2:", len(str2))

# ---------------- owner 帧级 + 录音级 LOO 真 / stranger 假 ----------------
owner_all = np.concatenate(list(owner_files.values()), axis=0)
all_str = np.concatenate(list(str1.values()) + list(str2.values()), axis=0)
tpl_full = np.mean(owner_all, axis=0).astype(np.int64)

# 帧级真/假
gen_frame = np.abs(owner_all - tpl_full).sum(axis=1)
imp_frame = np.abs(all_str - tpl_full).sum(axis=1)

# 录音级 LOO(每 owner 文件: 模板=其余14文件帧均值)
gen_utt, imp_utt = [], []
for key, fe in owner_files.items():
    others = np.concatenate([v for k, v in owner_files.items() if k != key], axis=0)
    t = np.mean(others, axis=0).astype(np.int64)
    mu = np.mean(fe, axis=0).astype(np.int64)
    gen_utt.append(l1(mu, t))
for key, fe in {**str1, **str2}.items():
    imp_utt.append(l1(np.mean(fe, axis=0).astype(np.int64), tpl_full))

def stats(a):
    a = np.asarray(a, np.float64)
    return dict(mean=float(a.mean()), std=float(a.std()), min=float(a.min()),
                max=float(a.max()), median=float(np.median(a)))

def eer_from(fr):
    """帧级 EER: 对阈值扫描 FAR(t)=P(imp>t) FRR(t)=P(gen<=t)，找最近交点。"""
    lo = min(gen_frame.min(), imp_frame.min())
    hi = max(gen_frame.max(), imp_frame.max())
    best = None
    for t in range(int(lo), int(hi) + 1, 200):
        far = float(np.mean(imp_frame > t)); frr = float(np.mean(gen_frame <= t))
        d = abs(far - frr)
        if best is None or d < best[0]:
            best = (d, t, far, frr)
    return best

e = eer_from((gen_frame, imp_frame))

with open(os.path.join(OUT, "eval_speaker.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["metric", "owner", "impostor"])
    for name in ["mean", "std", "min", "max", "median"]:
        w.writerow(["frame_" + name, stats(gen_frame)[name], stats(imp_frame)[name]])
        w.writerow(["uttmean_" + name, stats(gen_utt)[name], stats(imp_utt)[name]])
    w.writerow(["frame_EER_t", e[1]]); w.writerow(["frame_FAR@t", e[2]])
    w.writerow(["frame_FRR@t", e[3]])
    w.writerow(["n_owner_frame", len(gen_frame)]); w.writerow(["n_imp_frame", len(imp_frame)])
    w.writerow(["n_owner_utt", len(gen_utt)]); w.writerow(["n_imp_utt", len(imp_utt)])

print("\n== Speaker (13×int16 L1 vs owner mean template) ==")
print("  owner frame mean=%7.0f std=%7.0f | imp frame mean=%7.0f std=%7.0f"
      % (gen_frame.mean(), gen_frame.std(), imp_frame.mean(), imp_frame.std()))
print("  owner uttmean mean=%7.0f | imp uttmean mean=%7.0f" % (np.mean(gen_utt), np.mean(imp_utt)))
print("  frame-EER near th=%d FAR=%.3f FRR=%.3f" % (e[1], e[2], e[3]))
print("  (帧级两分布重叠则说明该 baseline 帧级判别弱 —— 如实记录)")

# ---------------- 写 owner_template.mem(全 owner 帧均值) ----------------
def write_mem(path, vec):
    with open(path, "w") as fh:
        for v in vec:
            fh.write("%04x\n" % (np.int32(np.clip(v, -32768, 32767)) & 0xFFFF))
    print("  template ->", os.path.relpath(path, ROOT))

tm = np.round(np.mean(owner_all, axis=0)).astype(np.int64)
write_mem(os.path.join(ROOT, "data", "speaker", "owner_template.mem"), tm)

# ---------------- 命令: 分段实例 + leave-utterance-out argmin ----------------
cmd_files = {}
for cmd in ["forward", "left", "right", "stop"]:
    p = os.path.join(ROOT, "sounds", "owner_sound", "commands", cmd, cmd + ".m4a")
    L, _ = ag.load_mono(p)
    fe = full_features(L).astype(np.int64)
    _, rms = ag.frame_energy(L)
    runs = run_mask(rms)
    cmd_files[cmd] = (fe, runs)

# utterance 实例: 每个 run 的帧 (取该 run 的帧特征均值作为实例向量)
utt_cmd = {}      # cmd -> list of np vector(13) & frame count
for cmd, (fe, runs) in cmd_files.items():
    vs = []
    for (s, e) in runs:
        seg = fe[s:e]
        if len(seg) >= 3:
            vs.append(np.mean(seg, axis=0).astype(np.int64))
    utt_cmd[cmd] = vs
    print("cmd %-8s runs/utt=%d" % (cmd, len(vs)))

cmds = ["stop", "left", "right", "forward"]
pred = []; true = []
for test_cmd in cmds:
    for iu, v in enumerate(utt_cmd[test_cmd]):
        # LOO 模板: 该命令除当前实例外所有实例的帧均值(用原始帧均值在实例平均上)
        others = np.mean(utt_cmd[test_cmd][:iu] + utt_cmd[test_cmd][iu + 1:], axis=0).astype(np.int64) \
                 if len(utt_cmd[test_cmd]) > 1 else np.mean(utt_cmd[test_cmd], axis=0).astype(np.int64)
        tpl = {c: others if c == test_cmd else
               np.mean(utt_cmd[c], axis=0).astype(np.int64) for c in cmds}
        ds = {c: l1(v, tpl[c]) for c in cmds}
        best = min(ds, key=ds.get)
        true.append(test_cmd); pred.append(best)

from collections import Counter
acc = np.mean([t == p for t, p in zip(true, pred)])
conf = Counter((t, p) for t, p in zip(true, pred))
print("\n== Command leave-utterance-out argmin ==")
print("  accuracy=%.3f  n=%d" % (acc, len(true)))
labels = cmds
print("  confusion (true,pred):")
for t in labels:
    row = "  %-8s" % t + "".join("%6d" % conf[(t, p)] for p in labels)
    print(row)

with open(os.path.join(OUT, "eval_command.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["true", "pred"])
    for t, p in zip(true, pred):
        w.writerow([t, p])
    w.writerow(["accuracy", round(acc, 4)])
    w.writerow(["n", len(true)])

# 写 4 个真实命令模板 (全部实例均值 int16) → cmd_stop/left/right/forward.mem
for cmd in cmds:
    t = np.round(np.mean(utt_cmd[cmd], axis=0)).astype(np.int64)
    write_mem(os.path.join(ROOT, "data", "commands", "cmd_" + cmd + ".mem"), t)
print("\nAll done. outputs under", os.path.relpath(OUT, ROOT))
