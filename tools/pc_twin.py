# -*- coding: utf-8 -*-
"""
pc_twin.py   16 PC 端“数字孪生”演示/数据记录脚本（配合 top_system 遥测帧）
帧格式(每 TELEM_MS)：[0xAA][state][target][pos][chk]
  chk = 0xAA ^ state ^ target ^ pos
用法：
  python pc_twin.py COM7            # 控制台实时打印
  python pc_twin.py COM7 --plot     # 实时曲线(需 matplotlib)
"""
import sys
import time
import serial

HEAD = 0xAA


def parse(buf, rows):
    """在 buf 中滑动查找合法帧并弹出已消费字节。rows: 收到的(t,state,target,pos)列表。"""
    i = 0
    n = len(buf)
    while i + 4 < n:
        if buf[i] == HEAD:
            st, tg, po, ck = buf[i + 1], buf[i + 2], buf[i + 3], buf[i + 4]
            if ck == (HEAD ^ st ^ tg ^ po):
                rows.append((time.time(), st, tg, po))
                i += 5
                continue
        i += 1
    del buf[:i]


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else "COM7"
    do_plot = "--plot" in sys.argv
    ser = serial.Serial(port, 115200, timeout=0.1)
    print("已打开", port, "115200 8N1。遥测帧: [AA][state][target][pos][chk]")
    buf = bytearray()
    rows = []
    if do_plot:
        import matplotlib.pyplot as plt
        plt.ion()
        fig, ax = plt.subplots()
        (line,) = ax.plot([], [])
        ax.set_ylim(0, 200); ax.set_ylabel("deg"); ax.set_xlabel("time (s)")
        ax.set_title("Virtual Motor: target / position")
    try:
        while True:
            data = ser.read(64)
            if data:
                buf.extend(data)
                parse(buf, rows)
                for t, st, tg, po in rows[-3:]:
                    print("%.3f  state=%d  target=%3d  pos=%3d" % (t % 1000, st, tg, po))
                if do_plot and len(rows) >= 2:
                    ts = [r[0] - rows[0][0] for r in rows]
                    line.set_data(ts, [r[3] for r in rows])   # pos
                    ax.set_xlim(0, max(ts) + 1)
                    ax.relim(); ax.autoscale_view(scaley=False)
                    fig.canvas.draw(); fig.canvas.flush_events()
            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        print("\n共收到 %d 帧" % len(rows))


if __name__ == "__main__":
    main()
