#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#------------------------------------------------------------------------------
# decode_cap_mem.py  板上真值采集(M-line) → 模板 .mem + 208-bit 参数字面量 + 距离分析
#
# 输入: 串口日志(SSCOM/任意终端保存的文本)。每段 VAD 语音一行, 支持两种形态:
#   A) 原始 M-line: 'M'+112hex(字段0=帧数, 字段1..13=dim0..12 的 int32 和)+'\n'
#   B) SSCOM 行:  [10:35:17.273]收←◆4D 30 30 ... 0A   (自动 fromhex 解码)
# 组页眉(可选):  '属主"机器人 你好":' / '陌生人"前进":' —— 其后到下一个页眉的段归该组。
#
# 中文词→规范化名: 机器人 你好→owner, 前进→forward, 停止→stop, 左转→left, 右转→right
# 角色前缀:        属主→属主发音; 陌生人→冒充者发音。
#
# 输出:
#   1) 每组均值模板 → data/speaker/owner_template.mem(属主"机器人 你好")
#                       data/commands/cmd_{forward,stop,left,right}.mem(属主命令词)
#   2) RTL 内嵌 208-bit 字面量(粘贴 cmd_matcher.v TPL0-3 / speaker_verify.v TPLV)
#   3) 距离分析表(SPK_TH 依据 + 命令可分离性):
#      - 组内距离: 同人同词各段 vs 组模板   → max_own
#      - 冒充/异词距离: 各非属主段 vs owner 模板 → min_imp
#      - 命令判别: 每段 argmin 到 4 个命令模板(计入 WHAT 判别真实水平)
#
# 用法:
#   python tools/decode_cap_mem.py capture2_clean.txt [--out_dir .]
#------------------------------------------------------------------------------
import argparse
import math
import os
import re
import sys

N_DIM = 13

# 组页眉: 角色"词":
HEADER_RE = re.compile(r'^\s*(属主|陌生人|.\S*)?"(.+?)"\s*:\s*$')
# 中文词 → 规范化输出名
CH_TO_NAME = {
    "机器人 你好": "owner",
    "前进": "forward",
    "停止": "stop",
    "左转": "left",
    "右转": "right",
}
ROLE_TO_TAG = {"属主": "owner", "陌生人": "imp"}


# ---------------- 解析 ----------------
def parse_mline(h):
    """h: 'M'+112hex → (cnt, sums[13]) 或 None"""
    if len(h) < 113 or h[0] != "M":
        return None
    try:
        cnt = int(h[1:9], 16)
        sums = []
        for k in range(N_DIM):
            s = int(h[9 + 8 * k: 17 + 8 * k], 16)
            if s & 0x80000000:
                s -= 0x100000000
            sums.append(s)
    except ValueError:
        return None
    return (cnt, sums)


def parse_log(path):
    """返回 (segs, meta)。segs: [(cnt,sums,group_key), ...]
       group_key: 规范名+角色 如 'imp/forward' 或 'owner/forward'; 无页眉时 None。"""
    segs = []
    cur_group = None
    n_raw = n_sscom = n_bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            ln = raw.rstrip("\r\n")

            mh = HEADER_RE.match(ln)
            if mh:
                role, word = mh.group(1), mh.group(2)
                role_tag = ROLE_TO_TAG.get(role, "?")
                name = CH_TO_NAME.get(word.strip(), word.strip().replace(" ", "_"))
                cur_group = f"{role_tag}/{name}"
                continue

            if not ln.strip():
                continue

            # 形态 B: SSCOM 行
            hexdump = None
            if "◆" in ln:
                dump = ln.split("◆", 1)[1].strip()
                if re.fullmatch(r"[0-9a-fA-F][0-9a-fA-F](?: [0-9a-fA-F][0-9a-fA-F])*", dump):
                    try:
                        hexdump = bytes.fromhex(dump).decode("ascii", errors="replace")
                    except ValueError:
                        hexdump = None
                if hexdump is not None:
                    n_sscom += 1
            elif ln.startswith("M") and re.fullmatch(r"M[0-9a-fA-F]{112}", ln):
                hexdump = ln
                n_raw += 1

            if hexdump is None:
                if ln.strip():
                    n_bad += 1
                continue

            pr = parse_mline(hexdump)
            if pr is None:
                n_bad += 1
                continue
            cnt, sums = pr
            # 截断/碎片防护: 短于 ~0.25s(≈180 帧) 记为 fragment 并跳过
            if cnt < 180:
                print(f"  [skip] 碎片段 cnt={cnt} 帧(≈{cnt*1.35:.0f}ms) 组={cur_group}")
                continue
            segs.append((cnt, sums, cur_group))
    return segs, (n_raw, n_sscom, n_bad)


# ---------------- 模板 ----------------
def to_int16(v):
    return max(-32768, min(32767, v))


def rnd(v):
    if v >= 0:
        return int(math.floor(v + 0.5))
    return int(math.ceil(v - 0.5))


def seg_mean(cnt, sums):
    if cnt <= 0:
        return [0] * N_DIM
    return [to_int16(rnd(s / cnt)) for s in sums]


def group_mean(means_list):
    n = len(means_list)
    if n == 0:
        return None
    return [to_int16(rnd(sum(m[d] for m in means_list) / n)) for d in range(N_DIM)]


def l1(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def literal(dims):
    v = 0
    for d in reversed(dims):
        v = (v << 16) | (d & 0xFFFF)
    return f"{v:052x}"


def write_mem(path, dims):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for d in dims:
            f.write(f"{d & 0xFFFF:04x}\n")


def dump(dims, tag):
    print(f"  [{tag}] 均值模板:")
    for d, v in enumerate(dims):
        print(f"    dim{d:2d} = {v:6d} (0x{v & 0xFFFF:04x})")
    print(f"    mem 文件写入完成")
    print(f"    208-bit 字面量 = 208'h{literal(dims)}")


# ---------------- 主流程 ----------------
def main():
    ap = argparse.ArgumentParser(description="板上真值 M-line → 模板 + 距离分析")
    ap.add_argument("log", help="串口日志(SSCOM 或裸 M-line)")
    ap.add_argument("--out_dir", default=".", help="输出根目录(默认当前目录)")
    args = ap.parse_args()

    segs, (n_raw, n_sscom, n_bad) = parse_log(args.log)
    if not segs:
        sys.exit("没有解析到任何有效 M-line — 检查日志格式")
    print(f"解析: 裸M行 {n_raw} / SSCOM 行 {n_sscom} / 丢弃 {n_bad} 行; 有效段 {len(segs)}")
    if n_bad:
        print(f"  (注意: {n_bad} 行无法解析或为碎片, 已跳过)")

    # 段均值
    seg_means = [seg_mean(c, s) for c, s, _ in segs]

    # 按组聚合
    from collections import OrderedDict
    groups = OrderedDict()
    for (cnt, _, gk), m in zip(segs, seg_means):
        key = gk if gk is not None else f"seg{len(groups)}"
        if key not in groups:
            groups[key] = {"cnt": 0, "segs": []}
        groups[key]["cnt"] += 1
        groups[key]["segs"].append((cnt, m))

    print(f"\n分组统计:")
    for k, g in groups.items():
        print(f"  {k:16s} {g['cnt']} 段  帧数={[c for c, _ in g['segs']]}")

    # 组模板
    tmpl = {k: group_mean([m for _, m in g["segs"]]) for k, g in groups.items()}

    # ---- 组内距离(同人同词稳定性) ----
    print("\n=== 组内 L1 距离 (各段 vs 本组均值模板) ===")
    max_own = 0
    intra = {}
    for k, g in groups.items():
        ds = [l1(tmpl[k], m) for _, m in g["segs"]]
        intra[k] = ds
        print(f"  {k:16s} 各段距离 {ds}  max={max(ds)}")
    # owner 组组内最大 → SPK_TH 下界
    if "owner/owner" in tmpl:
        max_own = max(intra["owner/owner"])
        print(f"\n  属主'机器人 你好' 组内最大距离 max_own = {max_own}")

    # ---- 冒充/异词 vs owner 模板 ----
    print("\n=== 非属主段 vs 属主'机器人 你好'模板 (冒充距离, SPK_TH 上界依据) ===")
    min_imp = None
    imp_rows = []
    if "owner/owner" in tmpl:
        o_t = tmpl["owner/owner"]
        for k, g in groups.items():
            if k == "owner/owner":
                continue
            for c, m in g["segs"]:
                d = l1(o_t, m)
                imp_rows.append((k, c, d))
                if min_imp is None or d < min_imp:
                    min_imp = d
        for k, c, d in sorted(imp_rows, key=lambda r: r[2]):
            print(f"  {k:16s} cnt={c:4d}  L1={d}")
        print(f"\n  min_imp = {min_imp}")

        if min_imp is not None:
            print(f"\n  SPK_TH 判别区间: max_own={max_own}  min_imp={min_imp}")
            if min_imp > max_own:
                mid = (max_own + min_imp) // 2
                print(f"  区间存在 → TH 可取 {max_own} ~ {min_imp}, 建议 ~{mid}")
            else:
                print("  !! 区间为空(数据缺口): owner 自己最远 vs 冒充者最近重叠, 如实报告")

    # ---- 命令可分离性(WHAT 判别) ----
    print("\n=== 命令判别 (每段 argmin → 4 命令模板; 测 WHAT 真实水平) ===")
    cmd_keys = [k for k in tmpl if k.startswith("owner/") and k != "owner/owner"]
    if len(cmd_keys) >= 2:
        conf = {k: 0 for k in cmd_keys}
        n_all = 0
        for k, g in groups.items():
            for c, m in g["segs"]:
                best = min(cmd_keys, key=lambda kk: l1(tmpl[kk], m))
                hit = "OK" if best == k else f"→{best.split('/')[-1]}"
                print(f"  {k:16s} cnt={c:4d}  最近={best.split('/')[-1]:8s} {hit}")
                n_all += 1
                if best == k:
                    conf[k] += 1
        print(f"\n  argmin 命中率: {sum(conf.values())}/{n_all} "
              f"({100.0 * sum(conf.values()) / n_all:.0f}%)  "
              f"各组={ {k.split('/')[-1]: v for k, v in conf.items()} }")

    # ---- 输出文件 ----
    print("\n=== 模板输出 ===")
    out = {}
    if "owner/owner" in tmpl:
        out["data/speaker/owner_template.mem"] = tmpl["owner/owner"]
    for w in ["forward", "stop", "left", "right"]:
        k = f"owner/{w}"
        if k in tmpl:
            out[f"data/commands/cmd_{w}.mem"] = tmpl[k]
    for rel, dims in out.items():
        p = os.path.join(args.out_dir, rel)
        write_mem(p, dims)
        dump(dims, rel)
        print()


if __name__ == "__main__":
    main()
