# -*- coding: utf-8 -*-
"""pcm_uart_receiver.py — 接收 PCM-over-UART，保存/绘制（无板子时为预案脚本）
用法: python tools/pcm_uart_receiver.py COM7 --out out.wav [--plot]
帧格式(参考 pcm_over_uart_design.md):
  AA n seq s0h s0l s1h s1l ... s(n-1)h s(n-1)l cs   (16bit 大端, n<=16)
缺帧/错校验丢弃并计数。
"""
import sys, argparse, time
import numpy as np

try:
    import serial
except ImportError:
    sys.exit("需要 pyserial")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--out", default=None)
    ap.add_argument("--plot", action="store_true")
    a = ap.parse_args()

    s = serial.Serial(a.port, a.baud, timeout=0.1)
    samples = []
    buf = b""
    ok = drop = 0
    print("接收中 Ctrl-C 停止")
    try:
        while True:
            buf += s.read(512)
            while len(buf) >= 3 and buf[0] != 0xAA:
                buf = buf[1:]
            if len(buf) >= 3:
                n = buf[1]
                need = 3 + 2 * n + 1
                if len(buf) >= need:
                    pkt, buf = buf[:need], buf[need:]
                    if pkt[2 + 2 * n] == (sum(pkt[:2 + 2 * n]) & 0xFF):  # 简单校验
                        for i in range(n):
                            v = (pkt[3 + 2 * i] << 8) | pkt[4 + 2 * i]
                            v = v - 65536 if v & 0x8000 else v
                            samples.append(v)
                        ok += 1
                    else:
                        drop += 1
            if a.plot and len(samples) > 200 and (len(samples) % 200 < n * 2):
                pass  # 提示：可交互绘制
    except KeyboardInterrupt:
        pass
    s.close()
    print(f"ok_pkt={ok} drop={drop} samples={len(samples)}")
    if a.out and samples:
        import wave, struct
        w = wave.open(a.out, "w")
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
        w.writeframes(b"".join(struct.pack("<h", int(x)) for x in samples))
        w.close()
        print("wrote", a.out)


if __name__ == "__main__":
    main()
