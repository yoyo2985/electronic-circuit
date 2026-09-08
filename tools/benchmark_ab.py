# -*- coding: utf-8 -*-
"""benchmark_ab.py — A(MFCC13+L1) vs B(CAM++ cosine)，含 full 与 leave-one-out 两模式
用法:
  python tools/benchmark_ab.py [--mode full|loo|both]   (默认 both)
输出 reports/*.csv/png/txt：
  comparison_campplus_vs_mfcc.csv / *_loo.csv / summary(full+loo) / roc|det .png 与 *_loo.png
LOO：owner 每轮留 1 测试、其余 14 均值做模板；impostor 24 逐轮对照模板（pool）。
诚实：本机无 ffmpeg → m4a 先 PyAV 转 16k wav 再喂 FunASR CAM++。
"""
import os, sys, glob, argparse, tempfile, wave, struct
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "py"))
FEAT = os.path.join(ROOT, "data", "speaker_features")
SOUND = os.path.join(ROOT, "sounds")
REP = os.path.join(ROOT, "reports")
os.makedirs(REP, exist_ok=True)


def rec_mean_mfcc(npz):
    f = np.load(npz)["features"].astype(np.int64)
    return np.clip(np.round(f.mean(0)), -32768, 32767).astype(np.int64)


def l1(a, b):
    return int(np.abs(np.asarray(a) - np.asarray(b)).sum())


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


def load_emb_cache(files):
    """对每个文件取 CAM++ 归一 embedding(缓存 dict name->emb)。"""
    from audio_golden import load_mono
    from funasr import AutoModel
    mdir = ("C:/Users/ZhongYOYO/.cache/modelscope/models/"
            "iic--speech_campplus_sv_zh-cn_16k-common/snapshots/master")
    if not os.path.isdir(mdir):
        sys.exit("CAM++ 快照缺失，先运行 tools/export_campplus_onnx.py")
    m = AutoModel(model=mdir, model_revision="master", device="cpu", disable_update=True)
    tmpd = tempfile.mkdtemp()
    out = {}
    for f in files:
        a = audio_of(f)
        if not a:
            out[os.path.basename(f)] = None
            continue
        if a.lower().endswith(".wav"):
            wav = a
        else:
            x16, _ = load_mono(a, 16000)
            wav = os.path.join(tmpd, os.path.basename(f)[:-4] + ".wav")
            w = wave.open(wav, "w")
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
            w.writeframes(b"".join(struct.pack("<h", int(v)) for v in x16))
            w.close()
        r = m.generate(input=wav)
        emb = np.asarray(r[0]["spk_embedding"].detach().cpu()).reshape(-1).astype(np.float64)
        n = np.linalg.norm(emb)
        out[os.path.basename(f)] = emb / n if n > 0 else emb
    return out


def eer(pos, neg, higher_better):
    pos = np.asarray(pos, float); neg = np.asarray(neg, float)
    lo = min(pos.min() if pos.size else 0, neg.min() if neg.size else 0)
    hi = max(pos.max() if pos.size else 0, neg.max() if neg.size else 0)
    best = (1.0, lo)
    for t in np.linspace(lo, hi, 5000):
        far = (neg >= t).mean() if higher_better else (neg <= t).mean()
        frr = (pos < t).mean() if higher_better else (pos > t).mean()
        e = abs(far - frr)
        if e < best[0]:
            best = (e, float(t))
    return best


def roc_data(pos, neg, higher_better):
    y = np.concatenate([np.ones(len(pos)), np.zeros(len(neg))])
    s = np.concatenate([np.array(pos), np.array(neg)])
    if higher_better:
        s = -s
    return y, s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["full", "loo", "both"], default="both")
    a = ap.parse_args()

    own, imp = list_recordings()
    own_names = [os.path.basename(f) for f in own]
    imp_names = [os.path.basename(f) for f in imp]
    A = {os.path.basename(f): rec_mean_mfcc(f) for f in own + imp}

    # ---- CAM++ embedding 缓存 ----
    print("loading CAM++ embeddings ...")
    E = load_emb_cache(own + imp)

    results = {}
    # ---------- FULL ----------
    if a.mode in ("full", "both"):
        tA = np.clip(np.round(np.mean([A[n] for n in own_names], 0)), -32768, 32767)
        fA_own = [l1(A[n], tA) for n in own_names]
        fA_imp = [l1(A[os.path.basename(f)], tA) for f in imp]
        tB = np.mean(np.stack([E[n] for n in own_names]), 0); tB /= (np.linalg.norm(tB) or 1)
        fB_own = [float(v @ tB) for v in (E[n] for n in own_names)]
        fB_imp = [float(E[os.path.basename(f)] @ tB) for f in imp]
        results["full"] = dict(A_own=fA_own, A_imp=fA_imp, B_own=fB_own, B_imp=fB_imp,
                               ea=eer(fA_own, fA_imp, False), eb=eer(fB_own, fB_imp, True))

    # ---------- LOO ----------
    if a.mode in ("loo", "both"):
        lA_own, lA_imp = [], []
        lB_own, lB_imp = [], []
        for o in own_names:
            others = [n for n in own_names if n != o]
            tA = np.clip(np.round(np.mean([A[n] for n in others], 0)), -32768, 32767)
            lA_own.append(l1(A[o], tA))
            tB = np.mean(np.stack([E[n] for n in others]), 0); tB /= (np.linalg.norm(tB) or 1)
            lB_own.append(float(E[o] @ tB))
            for n in imp_names:
                lA_imp.append(l1(A[n], tA))
                lB_imp.append(float(E[n] @ tB))
        results["loo"] = dict(A_own=lA_own, A_imp=lA_imp, B_own=lB_own, B_imp=lB_imp,
                              ea=eer(lA_own, lA_imp, False), eb=eer(lB_own, lB_imp, True))

    # ---------- 输出 ----------
    lines = []
    for mode in ("full", "loo"):
        if mode not in results:
            continue
        r = results[mode]
        note = ("本结果基于 leave-one-out 验证，更接近真实泛化能力"
                if mode == "loo" else "full(模板=全 owner 均值) — 乐观参考")
        lines.append(f"[{mode}] {note}")
        lines.append(f"  owner_test={len(r['A_own'])}  impostor对照数={len(r['A_imp'])}")
        lines.append(f"  A(MFCC L1) EER={r['ea'][0]:.3f} thr={r['ea'][1]:.0f}")
        lines.append(f"  B(CAM++ cos) EER={r['eb'][0]:.3f} thr={r['eb'][1]:.4f}")
        lines.append(f"  A own dist mean={np.mean(r['A_own']):.0f} imp mean={np.mean(r['A_imp']):.0f}")
        lines.append(f"  B own cos mean={np.mean(r['B_own']):.4f} imp mean={np.mean(r['B_imp']):.4f}")
    if "full" in results and "loo" in results:
        fa, fb = results["full"]["ea"][0], results["full"]["eb"][0]
        la, lb = results["loo"]["ea"][0], results["loo"]["eb"][0]
        lines.append("差异对比: full A=%.3f/B=%.3f  vs  LOO A=%.3f/B=%.3f"
                     % (fa, fb, la, lb))
    text = "\n".join(lines)
    print(text)
    with open(os.path.join(REP, "comparison_summary.txt"), "w", encoding="utf-8") as fo:
        fo.write(text + "\n")

    import csv
    def write_csv(suffix, mode):
        r = results[mode]
        with open(os.path.join(REP, f"comparison_campplus_vs_mfcc{suffix}.csv"), "w", newline="") as fo:
            w = csv.writer(fo)
            w.writerow(["file", "label", "A_dist", "B_sim"])
            for i, nm in enumerate(own_names):
                w.writerow([nm, "owner", r["A_own"][i], r["B_own"][i]])
            if mode == "loo":
                stride = len(imp_names)
                for j, nm in enumerate(imp_names):
                    am = np.median(r["A_imp"][j::stride])
                    bm = np.median(r["B_imp"][j::stride])
                    w.writerow([nm, "impostor", am, bm])
            else:
                for j, nm in enumerate(imp_names):
                    w.writerow([nm, "impostor", r["A_imp"][j], r["B_imp"][j]])
    if "full" in results:
        write_csv("", "full")
    if "loo" in results:
        write_csv("_loo", "loo")

    # 曲线
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.metrics import roc_curve, auc
        for mode in ("full", "loo"):
            if mode not in results:
                continue
            r = results[mode]
            for arm, hp in (("A", False), ("B", True)):
                y, s = roc_data(r[f"{arm}_own"], r[f"{arm}_imp"], hp)
                fp, tp, _ = roc_curve(y, s)
                plt.figure()
                plt.plot(fp, tp, label=f"{arm} auc={auc(fp,tp):.3f}")
                plt.plot([0, 1], [0, 1], "--"); plt.xlabel("FAR"); plt.ylabel("TAR"); plt.legend()
                plt.savefig(os.path.join(REP, f"roc_{mode.lower()}_{arm}.png"), dpi=120); plt.close()
    except Exception as ex:
        print("plot skipped:", repr(ex))
    print("done -> reports/comparison_summary.txt, csv/png(full & _loo)")


if __name__ == "__main__":
    main()
