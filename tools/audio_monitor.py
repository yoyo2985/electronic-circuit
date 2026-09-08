#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A1 音频状态监视器：读 top_audio 发的 "Pxxxx Lxxxx Rxxxx\n"（115200）。
P=该 0.5s 收到音频帧数(≈24000=codec 正常)，L/R=左右能量。
用法: python tools/audio_monitor.py COM7
只显示、不参与 FPGA 实时链路（符合项目红线）。"""
import sys, re

try:
    import serial
except ImportError:
    sys.exit("需要 pyserial:  pip install pyserial")

LINE = re.compile(r"P([0-9A-Fa-f]{4}) L([0-9A-Fa-f]{4}) R([0-9A-Fa-f]{4})")

def bars(v):
    v = min(v, 0xFFFF)
    n = round(v / 0xFFFF * 16)
    return "█" * n + "░" * (16 - n)

def main():
    port = sys.argv[1] if len(sys.argv) > 1 else "COM7"
    s = serial.Serial(port, 115200, timeout=0.2)
    print(f"监听 {port} @115200, Ctrl-C 退出\n")
    print("  P=每0.5s音频帧数(≈5DC0/24000 → codec正常)   L左  R右")
    buf = b""
    while True:
        try:
            data = s.read(256)
        except KeyboardInterrupt:
            break
        buf += data
        while b"\n" in buf:
            line, _, buf = buf.partition(b"\n")
            m = LINE.search(line.decode("ascii", "ignore"))
            if m:
                p = int(m.group(1), 16)
                l = int(m.group(2), 16)
                r = int(m.group(3), 16)
                sys.stdout.write("\r" + " " * 78 + "\r")
                sys.stdout.write(f"P:{p:5d}  L {bars(l)} {l:5}  |  R {bars(r)} {r:5}")
                sys.stdout.flush()

if __name__ == "__main__":
    main()
