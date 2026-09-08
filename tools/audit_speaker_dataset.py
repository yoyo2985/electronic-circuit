# -*- coding: utf-8 -*-
"""audit_speaker_dataset.py  — 声音数据集审计（不改原始文件）
遍历 sounds/，用 PyAV 读取每个 m4a：编码/采样率/声道/位深/时长/峰/RMS/是否疑似静音。
输出：控制台表格 + reports/speaker_verification/dataset_audit.txt
"""
import os, sys, glob, statistics
import numpy as np

try:
    import av
except ImportError:
    sys.exit("需要 PyAV:  pip install av")

ROOT = os.path.join(os.path.dirname(__file__), "..")
SOUNDS = os.path.join(ROOT, "sounds")
REP = os.path.join(ROOT, "reports", "speaker_verification")
os.makedirs(REP, exist_ok=True)


def read_mono(path, sr=48000):
    """解码为 48k mono float32（PyAV 重采样），返回 (x, orig_rate, ch, sample_fmt)."""
    c = av.open(path)
    st = c.streams.audio[0]
    cc = getattr(st, "codec_context", None)
    orig_rate = getattr(cc, "sample_rate", None) or getattr(st, "rate", None)
    ch = getattr(st, "channels", None)
    cfmt = getattr(getattr(cc, "format", None), "name", None) or str(getattr(st, "format", None))
    res = av.AudioResampler(format="s16", layout="mono", rate=sr)
    buf = []
    for frame in c.decode(audio=0):
        for f in res.resample(frame):
            arr = f.to_ndarray()          # (1, n) int16
            buf.append(arr[0].astype(np.int16))
    c.close()
    if not buf:
        return np.zeros(0, np.int16), orig_rate, ch, cfmt
    x = np.concatenate(buf)
    return x, orig_rate, ch, cfmt


def main():
    rows = []
    for spk in sorted(os.listdir(SOUNDS)):
        d = os.path.join(SOUNDS, spk)
        if not os.path.isdir(d):
            continue
        for f in sorted(glob.glob(os.path.join(d, "*"))):
            try:
                x, rate, ch, fmt = read_mono(f)
            except Exception as e:
                print("ERR", f, e)
                continue
            dur = len(x) / 48000.0
            peak = float(np.max(np.abs(x))) if x.size else 0
            rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2))) if x.size else 0
            quiet = peak < 500   # 粗略静音（int16 域）
            rows.append(dict(spk=spk, file=os.path.basename(f), rate=rate, ch=ch,
                             fmt=fmt, dur=round(dur, 2), peak=int(peak), rms=round(rms, 1),
                             quiet=quiet))
    # 汇总
    lines = []
    hdr = f"{'speaker':<12}{'file':<22}{'rate':>6}{'ch':>4}{'fmt':<8}{'dur_s':>8}{'peak':>8}{'rms':>9}{'quiet':>7}"
    lines.append(hdr); lines.append('-' * len(hdr))
    for r in rows:
        lines.append(f"{r['spk']:<12}{r['file']:<22}{r['rate']:>6}{r['ch']:>4}{str(r['fmt']):<8}{r['dur']:>8}{r['peak']:>8}{r['rms']:>9}{str(r['quiet']):>7}")
    n = len(rows)
    lines.append('-' * len(hdr))
    spk_cnt = {}
    for r in rows:
        spk_cnt[r['spk']] = spk_cnt.get(r['spk'], 0) + 1
    lines.append("文件总数=%d" % n)
    for k in sorted(spk_cnt):
        lines.append("  %s = %d" % (k, spk_cnt[k]))
    if rows:
        rates = set(r['rate'] for r in rows)
        chs = set(r['ch'] for r in rows)
        lines.append("采样率集=%s 声道集=%s" % (sorted(rates), sorted(chs)))
        lines.append("静音/极弱文件=%d" % sum(1 for r in rows if r['quiet']))
    txt = "\n".join(lines)
    print(txt)
    with open(os.path.join(REP, "dataset_audit.txt"), "w", encoding="utf-8") as fo:
        fo.write(txt + "\n")


if __name__ == "__main__":
    main()
