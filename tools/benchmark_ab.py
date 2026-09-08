# -*- coding: utf-8 -*-
"""benchmark_ab.py — 全量 owner/impostor A(MFCC13+L1) vs B(CAM++ cosine)
owner 全部 15 条, impostor 24 条(本次不划分，注册模板=全部 owner 的均值)。
A 模板: MFCC 录音级均值(全量); B 模板: CAM++ embedding 均值(全量)。
输出 CSV / 摘要 / ROC/DET png。诚实：注册含测试身份→结果略乐观，仅作参考。
"""
import os, sys, glob
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
FEAT = os.path.join(ROOT, "data", "speaker_features")
SOUND = os.path.join(ROOT, "sounds")
REP = os.path.join(ROOT, "reports")
os.makedirs(REP, exist_ok=True)

MF = os.path.join(ROOT, "py", "campplus", "models", "campplus_emb.onnx")


def read_tpl16(p):
    v = []
    for l in open(p):
        l = l.strip()
        if l:
            x = int(l, 16)
            v.append(x - 0x10000 if x & 0x8000 else x)
    return np.array(v, np.int64)


def rec_mean_mfcc(npz):
    f = np.load(npz)["features"].astype(np.int64)
    return np.clip(np.round(f.mean(0)), -32768, 32767).astype(np.int64)


def l1(a, b):
    return int(np.abs(np.asarray(a) - np.asarray(b)).sum())


def eer_1d(pos, neg):
    lo = min(pos.min(), neg.min()); hi = max(pos.max(), neg.max())
    best = (1.0, lo)
    for t in np.linspace(lo, hi, 4000):
        far = (neg <= t).mean(); frr = (pos > t).mean()
        if abs(far - frr) < best[0]:
            best = (abs(far - frr), float(t))
    return best


def list_recordings():
    own = sorted(glob.glob(os.path.join(FEAT, "owner_sound", "*.npz")))
    imp = []
    for s in ("stranger1", "stranger2"):
        imp += sorted(glob.glob(os.path.join(FEAT, s, "*.npz")))
    return own, imp


def audio_of(npz):
    spk = os.path.basename(os.path.dirname(npz))
    stem = os.path.basename(npz)[:-4]
    for ext in (".m4a", ".wav"):
        p = os.path.join(SOUND, spk, stem + ext)
        if os.path.exists(p):
            return p
    return None


def campplus_scores(files):
    from funasr import AutoModel
    import wave, struct, tempfile
    sys.path.insert(0, os.path.join(ROOT, "py"))
    from audio_golden import load_mono
    mdir = ("C:/Users/ZhongYOYO/.cache/modelscope/models/"
            "iic--speech_campplus_sv_zh-cn_16k-common/snapshots/master")
    if not os.path.isdir(mdir):
        sys.exit("CAM++ 快照缺失，请先运行 export_campplus_onnx.py/下载")
    m = AutoModel(model=mdir, model_revision="master", device="cpu", disable_update=True)
    tmpd = tempfile.mkdtemp()
    embs = {}
    for f in files:
        a = audio_of(f)
        if not a:
            embs[os.path.basename(f)] = None
            continue
        if a.lower().endswith(".wav"):
            wav = a
        else:
            x16, _ = load_mono(a, 16000)      # PyAV 解码→16k int16 L
            wav = os.path.join(tmpd, os.path.basename(f)[:-4] + ".wav")
            w = wave.open(wav, "w")
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
            w.writeframes(b"".join(struct.pack("<h", int(v)) for v in x16))
            w.close()
        r = m.generate(input=wav)
        emb = np.asarray(r[0]["spk_embedding"].detach().cpu()).reshape(-1).astype(np.float64)
        n = np.linalg.norm(emb)
        embs[os.path.basename(f)] = emb / n if n > 0 else emb
    return embs


def main():
    own, imp = list_recordings()
    own_names = [os.path.basename(f) for f in own]
    # A 臂
    A = {os.path.basename(f): rec_mean_mfcc(f) for f in own + imp}
    tA = np.clip(np.round(np.mean([A[n] for n in own_names], 0)), -32768, 32767)
    A_own = [l1(A[n], tA) for n in own_names]
    A_imp = [l1(A[os.path.basename(f)], tA) for f in imp]

    # B 臂 (CAM++)
    emb = campplus_scores(own + imp)
    tB = np.mean(np.stack([emb[n] for n in own_names]), 0)
    tB = tB / (np.linalg.norm(tB) or 1)
    B = {k: float(v @ tB) if v is not None else float("nan") for k, v in emb.items()}
    B_own = [B[n] for n in own_names]
    B_imp = [B[os.path.basename(f)] for f in imp]

    ea = eer_1d(np.array(A_own), np.array(A_imp))
    eb = eer_1d(np.array(B_own), np.array(B_imp))

    lines = []
    lines.append(f"owner={len(own)} impostor={len(imp)}")
    lines.append(f"A(MFCC L1) EER={ea[0]:.3f} thr={ea[1]:.0f}")
    lines.append(f"B(CAM++ cos) EER={eb[0]:.3f} thr={eb[1]:.4f}")
    lines.append("A owner dist: mean=%.0f min=%.0f max=%.0f" %
                 (np.mean(A_own), min(A_own), max(A_own)))
    lines.append("A impostor dist: mean=%.0f min=%.0f max=%.0f" %
                 (np.mean(A_imp), min(A_imp), max(A_imp)))
    lines.append("B owner cos: mean=%.4f min=%.4f max=%.4f" %
                 (np.mean(B_own), min(B_own), max(B_own)))
    lines.append("B impostor cos: mean=%.4f min=%.4f max=%.4f" %
                 (np.mean(B_imp), min(B_imp), max(B_imp)))
    text = "\n".join(lines)
    print(text)
    with open(os.path.join(REP, "comparison_summary.txt"), "w", encoding="utf-8") as fo:
        fo.write(text + "\n")

    import csv
    with open(os.path.join(REP, "comparison_campplus_vs_mfcc.csv"), "w", newline="") as fo:
        w = csv.writer(fo)
        w.writerow(["file", "label", "A_dist", "B_sim"])
        for n, d in zip(own_names, A_own):
            w.writerow([n, "owner", d, B[n]])
        for f, d in zip(imp, A_imp):
            w.writerow([os.path.basename(f), "impostor", d, B[os.path.basename(f)]])

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.metrics import roc_curve, auc  # 可选
        # ROC
        y = np.concatenate([np.ones(len(A_own)), np.zeros(len(A_imp))])
        sA = np.concatenate([np.max(A_own) - np.array(A_own), np.max(A_imp) - np.array(A_imp)])
        sB = np.concatenate([np.array(B_own), np.array(B_imp)])
        fA, tA2, _ = roc_curve(y, sA); fB, tB2, _ = roc_curve(y, sB)
        plt.figure(); plt.plot(fA, tA2, label=f"A MFCC auc={auc(fA,tA2):.2f}")
        plt.plot(fB, tB2, label=f"B CAM++ auc={auc(fB,tB2):.2f}")
        plt.plot([0, 1], [0, 1], "--"); plt.xlabel("FAR"); plt.ylabel("TAR")
        plt.legend(); plt.savefig(os.path.join(REP, "roc_comparison.png"), dpi=120)
        plt.close()
        # DET(FAR vs FRR)
        frrA = 1 - tA2; frrB = 1 - tB2
        plt.figure(); plt.plot(fA, frrA, label="A MFCC")
        plt.plot(fB, frrB, label="B CAM++")
        plt.xscale("log"); plt.xlabel("FAR"); plt.ylabel("FRR")
        plt.legend(); plt.savefig(os.path.join(REP, "det_comparison.png"), dpi=120)
        plt.close()
        print("plots -> reports/roc_comparison.png, det_comparison.png")
    except Exception as ex:
        print("plot skipped:", repr(ex))


if __name__ == "__main__":
    main()
