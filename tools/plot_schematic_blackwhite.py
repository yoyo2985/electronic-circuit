# -*- coding: utf-8 -*-
"""
plot_schematic_blackwhite.py
基于 EG4S20BG256 核心板真实原理图（EG4S20BG256核心板 - 2023.pdf）绘制
论文/技术报告风格黑白原理图。

所有引脚号 / 网络名 / 元件位号与参数均逐项由 pymupdf 从原理图 PDF 中提取核对：

  供电页(P4)：VBUS→F1(SMD1812P050TF)→5V；D9(SS54) 为反接钳位(阴极接 5V、阳极接 GND)；
             R81(2.21k)+POWER2 红色 LED 由 5V 到 GND；
             U5/U6 RT8097CHGB 五脚(1=EN,2=GND,3=LX,4=VIN,5=FB)，EN 与 VIN 同接 5V；
             U5→L1(SWPA6028S4R7MT)→FPGA1.2V(C10 22µF,C11~C13 4.7µF)，FB 分压 R83/R84(10.0k)；
             U6→L3(SWPA6028S4R7MT)→FPGA3.3V(C17 22µF,C18~C20 4.7µF)，FB 分压 R85(10.0k)/R86(49.9k)；
             L4(120Ω) 连接 FPGA3.3V 与 3.3V，两侧 C21(4.7µF)/C22(0.1µF)；
             U11 LD1117-3.3(1=GND,2=Vout,3=Vin,4=NC)：5V→OUT_3.3V，C55(4.7µF) 输入，
             C15(4.7µF)/C16(0.1µF) 输出。
  配置页(P1)：U8 M25P16(1=CS,2=DO/IO1,3=WP/IO2,4=GND,5=DI/IO0,6=CLK,7=HOLD/IO3,8=VCC)；
             U7E 配置 Bank：CSO_B=T3, CCLK=R11, MOSI=T10, D0/DIN=P10,
             INIT_B=R3, DONE=P13, PROGRAM_B=T2, M0=T11, M1=N11；
             上拉 R95/R96 2.21k(WP/HOLD→FPGA3.3V)，R88~R91 10.0k，R92/R93 470Ω(M0→3.3V, M1→GND)；
             C47 0.1µF 为 U8 退耦；JTAG：TCK=C14(R77), TDO=E14(R78), TMS=A15(R76), TDI=C12(R79)。
  时钟页(P1)：Y3 7X-50.000MBB-T(1=E/C,2=GND,3=OUT,4=VDD)，C35 0.1µF 退耦，
             OUT→R97(22.1Ω)→FPGA_GCLK1→T8。
  接口页(P2/P3)：U2 CH340N(1=UD+,2=UD-,3=GND,4=RTS#,5=VCC,6=TXD,7=RXD,8=V3)，
             TXD→网RXD→FPGA F12，RXD→网TXD→FPGA D12；
             U4 GD32F150G8U6：PA13/PA14/PA15/PB3/PB4 为 JTAG 口，经 R76~R79 0Ω 接 FPGA；
             PA12→R66(22.1Ω)→USB_D+，PA11→R67(22.1Ω)→USB_D-；
             PA9→R71(0Ω)→USART_TX→FPGA C13，PA10→R70(0Ω)→USART_RX→FPGA E12；
             U1 SGM321YN5/TR(1=OUT,2=V-,3=IN+,4=IN-,5=V+) 运放，R45 1.00k 反馈，C1 0.1µF；
             R46~R53 20.0k 串联臂，R56~R62 为 R-2R 网络；输出经 J1(2 脚) 引出 DAC_VOUT。
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon, Circle, Arc

for _f in ["Microsoft YaHei", "SimHei", "SimSun", "Noto Sans CJK SC"]:
    try:
        matplotlib.font_manager.findfont(_f, fallback_to_default=False)
        plt.rcParams["font.family"] = [_f, "DejaVu Sans"]
        break
    except Exception:
        continue
plt.rcParams["axes.unicode_minus"] = False

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fig_sch")
os.makedirs(OUT, exist_ok=True)

BLACK = "black"


class Fig:
    def __init__(self, w, h):
        self.fig, self.ax = plt.subplots(figsize=(w, h))
        self.ax.set_aspect("equal")
        self.ax.axis("off")
        self.fig.subplots_adjust(left=0.0, right=1.0, top=1.0, bottom=0.0)

    def line(self, x0, y0, x1, y1, lw=1.2):
        self.ax.plot([x0, x1], [y0, y1], color=BLACK, lw=lw,
                     solid_capstyle="butt", zorder=3)

    def hwire(self, x0, x1, y, lw=1.2):
        self.line(x0, y, x1, y, lw=lw)

    def vwire(self, x, y0, y1, lw=1.2):
        self.line(x, y0, x, y1, lw=lw)

    def rect(self, x, y, w, h, lw=1.4):
        self.ax.add_patch(Rectangle((x, y), w, h, fill=False, ec=BLACK,
                                    fc="white", lw=lw, zorder=3))

    def poly(self, pts, lw=1.1, fill=True):
        self.ax.add_patch(Polygon(pts, closed=True, ec=BLACK,
                                  fc="white" if fill else "none", lw=lw, zorder=4))

    def text(self, x, y, s, size=7.8, ha="center", va="center", bold=False,
             rot=0):
        self.ax.text(x, y, s, fontsize=size, ha=ha, va=va, rotation=rot,
                     color=BLACK, fontweight="bold" if bold else "normal",
                     zorder=6)

    def dot(self, x, y, r=0.07):
        self.ax.add_patch(Circle((x, y), r, fc=BLACK, ec=BLACK, zorder=6))

    def save(self, name):
        for ext in ("pdf", "png"):
            self.fig.savefig(os.path.join(OUT, name + "." + ext), dpi=200,
                             facecolor="white", bbox_inches="tight",
                             pad_inches=0.12)
        plt.close(self.fig)
        print("  saved:", name)


# ---------------------------------------------------------------- 符号
def _lab(f, x, y, value, ref, vert, vpos, rpos):
    """元件值/位号标注。vpos/rpos 为 (dx, dy, ha, va)，缺省按横/竖放置。"""
    if value:
        if vpos:
            f.text(x + vpos[0], y + vpos[1], value, size=7.2, ha=vpos[2], va=vpos[3])
        elif vert:
            f.text(x + 0.55, y, value, size=7.2, ha="left")
        else:
            f.text(x, y - 0.46, value, size=7.2)
    if ref:
        if rpos:
            f.text(x + rpos[0], y + rpos[1], ref, size=7.2, ha=rpos[2], va=rpos[3])
        elif vert:
            f.text(x - 0.55, y, ref, size=7.2, ha="right")
        else:
            f.text(x, y + 0.46, ref, size=7.2)


def resistor(f, x, y, value=None, ref=None, horizontal=True, L=0.7, H=0.42,
             lead=0.3, vpos=None, rpos=None):
    """空心矩形电阻。返回 (a, b) 两端引线端点。"""
    if horizontal:
        a, b = (x - L / 2 - lead, y), (x + L / 2 + lead, y)
        f.hwire(a[0], x - L / 2, y)
        f.hwire(x + L / 2, b[0], y)
        f.rect(x - L / 2, y - H / 2, L, H)
    else:
        a, b = (x, y + L / 2 + lead), (x, y - L / 2 - lead)
        f.vwire(x, y + L / 2, a[1])
        f.vwire(x, b[1], y - L / 2)
        f.rect(x - H / 2, y - L / 2, H, L)
    _lab(f, x, y, value, ref, not horizontal, vpos, rpos)
    return a, b


def capacitor(f, x, y, value=None, ref=None, horizontal=True, plate=0.5,
              gap=0.16, lead=0.25, vpos=None, rpos=None):
    """双平行板电容。返回 (a, b)。"""
    if horizontal:
        a, b = (x - plate / 2 - gap - lead, y), (x + plate / 2 + gap + lead, y)
        f.hwire(a[0], x - plate / 2 - gap, y)
        f.hwire(x + plate / 2 + gap, b[0], y)
        f.line(x - plate / 2 - gap, y - plate / 2, x - plate / 2 - gap, y + plate / 2, lw=1.1)
        f.line(x + plate / 2 + gap, y - plate / 2, x + plate / 2 + gap, y + plate / 2, lw=1.1)
    else:
        a, b = (x, y + plate / 2 + gap + lead), (x, y - plate / 2 - gap - lead)
        f.vwire(x, y + plate / 2 + gap, a[1])
        f.vwire(x, b[1], y - plate / 2 - gap)
        f.line(x - plate / 2, y - plate / 2 - gap, x + plate / 2, y - plate / 2 - gap, lw=1.1)
        f.line(x - plate / 2, y + plate / 2 + gap, x + plate / 2, y + plate / 2 + gap, lw=1.1)
    _lab(f, x, y, value, ref, not horizontal, vpos, rpos)
    return a, b


def ferrite(f, x, y, value=None, ref=None, horizontal=True, L=0.9, H=0.5,
            lead=0.3, n=3, vpos=None, rpos=None):
    """磁珠/电感：半圆弧绕组。返回 (a, b)。"""
    if horizontal:
        a, b = (x - L / 2 - lead, y), (x + L / 2 + lead, y)
        f.hwire(a[0], x - L / 2, y)
        f.hwire(x + L / 2, b[0], y)
        for i in range(n):
            cx = x - L / 2 + L * (i + 0.5) / n
            f.ax.add_patch(Arc((cx, y), L / n * 0.92, H, angle=0, theta1=0,
                               theta2=180, ec=BLACK, lw=1.1, zorder=3))
    else:
        a, b = (x, y + L / 2 + lead), (x, y - L / 2 - lead)
        f.vwire(x, y + L / 2, a[1])
        f.vwire(x, b[1], y - L / 2)
        for i in range(n):
            cy = y - L / 2 + L * (i + 0.5) / n
            f.ax.add_patch(Arc((x, cy), H, L / n * 0.92, angle=0, theta1=180,
                               theta2=360, ec=BLACK, lw=1.1, zorder=3))
    _lab(f, x, y, value, ref, not horizontal, vpos, rpos)
    return a, b


def diode(f, x, y, value=None, ref=None, direction="down", L=0.7, W=0.6,
          lead=0.3, vpos=None, rpos=None):
    """二极管，三角指向 direction（即阴极侧）。返回 (a, b)：a 为阳极侧。"""
    h = L / 2
    if direction in ("down", "up"):
        sgn = -1 if direction == "down" else 1
        a = (x, y + sgn * (h + lead))
        b = (x, y - sgn * (h + lead))
        f.vwire(x, a[1], y + sgn * h)
        f.vwire(x, y - sgn * h, b[1])
        tip = y + sgn * (h - 0.06)
        base = y - sgn * h
        f.poly([(x - W / 2, base), (x + W / 2, base), (x, tip)])
        f.line(x - W / 2, tip, x + W / 2, tip, lw=1.3)
    else:
        sgn = 1 if direction == "right" else -1
        a = (x - sgn * (h + lead), y)
        b = (x + sgn * (h + lead), y)
        f.hwire(a[0], x - sgn * h, y)
        f.hwire(x + sgn * h, b[0], y)
        tip = x + sgn * (h - 0.06)
        base = x - sgn * h
        f.poly([(base, y - W / 2), (base, y + W / 2), (tip, y)])
        f.line(tip, y - W / 2, tip, y + W / 2, lw=1.3)
    _lab(f, x, y, value, ref, direction in ("down", "up"), vpos, rpos)
    return a, b


def led_down(f, x, y):
    """发光二极管（向下），返回底端 y。"""
    f.poly([(x - 0.22, y), (x + 0.22, y), (x, y - 0.42)])
    f.line(x - 0.22, y - 0.42, x + 0.22, y - 0.42, lw=1.3)
    f.line(x + 0.26, y - 0.10, x + 0.44, y - 0.28, lw=1.0)
    f.line(x + 0.36, y - 0.02, x + 0.52, y - 0.18, lw=1.0)
    return y - 0.42


def gnd(f, x, y):
    """接地符号：(x, y) 为连接点，符号在下方。"""
    f.vwire(x, y, y - 0.22, lw=1.1)
    for i, w in enumerate((0.62, 0.42, 0.22)):
        yy = y - 0.22 - 0.11 * i
        f.line(x - w / 2, yy, x + w / 2, yy, lw=1.1)


def vcc(f, x, y, label=None, bar=0.7):
    """电源符号：(x, y) 为连接点，符号在上方。"""
    f.vwire(x, y, y + 0.28, lw=1.1)
    f.line(x - bar / 2, y + 0.28, x + bar / 2, y + 0.28, lw=1.1)
    if label:
        f.text(x + bar / 2 + 0.16, y + 0.28, label, size=7.2, ha="left")


class Chip:
    """矩形芯片框；left/right 为 (引脚号, 引脚名) 或 (引脚号, 引脚名, y)。
    自动按 n+1 等分纵排；返回 self，pins['L'/'R'/...][引脚号] = (引线外端点)。"""

    def __init__(self, f, x, y, w, h, name, left=None, right=None, top=None,
                 bottom=None, pin_len=0.45, name_size=9.0, pn_size=6.8,
                 num_size=7.0, name_ha=None):
        self.f, self.x, self.y, self.w, self.h = f, x, y, w, h
        self.pin_len = pin_len
        f.rect(x, y, w, h, lw=1.5)
        if name:
            f.text(x + w / 2, y + h / 2, name, size=name_size, bold=True)
        self.pins = {"L": {}, "R": {}, "T": {}, "B": {}}
        self._side(left or [], "L", pin_len, pn_size, num_size)
        self._side(right or [], "R", pin_len, pn_size, num_size)
        self._side(top or [], "T", pin_len, pn_size, num_size)
        self._side(bottom or [], "B", pin_len, pn_size, num_size)

    def _side(self, pins, side, pin_len, pn_size, num_size):
        f = self.f
        n = len(pins)
        for i, p in enumerate(pins):
            num, nm = p[0], p[1]
            if side in ("L", "R"):
                py = p[2] if len(p) > 2 and p[2] is not None else \
                    self.y + self.h - self.h * (i + 1) / (n + 1)
            else:
                px = p[2] if len(p) > 2 and p[2] is not None else \
                    self.x + self.w * (i + 1) / (n + 1)
            if side == "L":
                f.hwire(self.x - pin_len, self.x, py)
                f.text(self.x - 0.10, py + 0.10, str(num), size=num_size,
                       ha="right", va="bottom")
                if nm:
                    f.text(self.x + 0.14, py, nm, size=pn_size, ha="left")
                self.pins["L"][num] = (self.x - pin_len, py)
            elif side == "R":
                f.hwire(self.x + self.w, self.x + self.w + pin_len, py)
                f.text(self.x + self.w + 0.10, py + 0.10, str(num),
                       size=num_size, ha="left", va="bottom")
                if nm:
                    f.text(self.x + self.w - 0.14, py, nm, size=pn_size,
                           ha="right")
                self.pins["R"][num] = (self.x + self.w + pin_len, py)
            elif side == "T":
                f.vwire(px, self.y + self.h, self.y + self.h + pin_len)
                f.text(px + 0.12, self.y + self.h + 0.10, str(num),
                       size=num_size, ha="left", va="bottom")
                if nm:
                    f.text(px, self.y + self.h - 0.14, nm, size=pn_size,
                           va="top")
                self.pins["T"][num] = (px, self.y + self.h + pin_len)
            else:
                f.vwire(px, self.y, self.y - pin_len)
                f.text(px + 0.12, self.y - 0.10, str(num), size=num_size,
                       ha="left", va="top")
                if nm:
                    f.text(px, self.y + 0.14, nm, size=pn_size, va="bottom")
                self.pins["B"][num] = (px, self.y - pin_len)


def netlabel(f, x, y, s, size=7.4, ha="center", va="bottom", dy=0.12, rot=0):
    f.text(x, y + dy, s, size=size, ha=ha, va=va, rot=rot)


# ======================================================================
#  图 1 —— FPGA 供电电路
# ======================================================================
def fig_power():
    f = Fig(22.2, 16.4)
    f.text(10.5, 14.35, "FPGA Power Supply Circuit  (FPGA 供电电路)",
           size=13, bold=True)

    RY = 12.9                                   # 输入链所在行
    # ---- VBUS → F1 → 5V 母线 ----
    f.hwire(0.6, 1.35, RY)
    f.text(0.6, RY + 0.30, "VBUS", size=8, ha="left", bold=True)
    resistor(f, 2.1, RY, value="SMD1812P050TF", ref="F1")
    f.hwire(2.85, 9.8, RY)
    f.text(3.35, RY + 0.30, "5V", size=8, ha="left", bold=True)

    # ---- D9 反接钳位：阴极接 5V，阳极接 GND ----
    f.dot(7.2, RY)
    diode(f, 7.2, 11.85, value="SS54", ref="D9", direction="up",
          vpos=(0.40, -0.14, "left", "center"), rpos=(0.40, 0.16, "left", "center"))
    f.vwire(7.2, RY, 12.50)
    f.vwire(7.2, 11.20, 11.00)
    gnd(f, 7.2, 11.00)

    # ---- R81 + POWER2 红色 LED ----
    f.dot(9.6, RY)
    f.vwire(9.6, RY, 12.10)
    resistor(f, 9.6, 11.45, value="2.21k", ref="R81", horizontal=False,
             vpos=(0.42, -0.30, "left", "center"), rpos=(0.42, 0.02, "left", "center"))
    yb = led_down(f, 9.6, 10.80)
    f.vwire(9.6, yb, 10.10)
    gnd(f, 9.6, 10.10)
    f.text(10.0, 10.55, "POWER2", size=7.2, ha="left")
    f.text(10.0, 10.25, "红色 LED", size=7.2, ha="left")

    # ---- 5V 立管（供 U5 / U6 / U11）----
    f.vwire(3.2, RY, 0.47)
    f.dot(3.2, RY)

    # ---- U5 RT8097CHGB → FPGA1.2V ----
    u5 = Chip(f, 5.6, 7.6, 3.0, 2.2, "U5\nRT8097CHGB",
              left=[("4", "VIN", 9.07), ("1", "EN", 8.33)],
              right=[("3", "LX", 9.07), ("5", "FB", 8.33)],
              bottom=[("2", "GND", 7.1)])
    f.hwire(3.2, u5.pins["L"]["4"][0], 9.07)
    f.dot(3.2, 9.07)
    f.hwire(3.2, u5.pins["L"]["1"][0], 8.33)
    f.dot(3.2, 8.33)
    f.vwire(7.1, 7.6, 7.30)
    gnd(f, 7.1, 7.30)

    f.hwire(u5.pins["R"]["3"][0], 9.85, 9.07)
    ferrite(f, 10.5, 9.07, value="SWPA6028S4R7MT", ref="L1")
    f.hwire(11.15, 17.4, 9.07)
    f.text(17.6, 9.07, "+1.2V\n(VCCINT)", size=7.8, ha="left", bold=True)

    for cx, c in zip((12.8, 14.0, 15.2, 16.4),
                     ("C10 22µF", "C11 4.7µF", "C12 4.7µF", "C13 4.7µF")):
        f.dot(cx, 9.07)
        f.vwire(cx, 9.07, 8.47)
        capacitor(f, cx, 7.81, horizontal=False)
        f.vwire(cx, 7.15, 6.80)
        gnd(f, cx, 6.80)
        f.text(cx - 0.52, 7.81, c, size=6.8, rot=90)

    # U5 FB 分压 R83 / R84
    f.dot(11.7, 9.07)
    f.vwire(11.7, 9.07, 8.47)
    resistor(f, 11.7, 7.81, value="10.0k", ref="R83", horizontal=False,
             vpos=(-0.34, -0.14, "right", "center"),
             rpos=(-0.34, 0.16, "right", "center"))
    f.vwire(11.7, 7.15, 7.00)
    f.dot(11.7, 7.07)
    resistor(f, 11.7, 6.34, value="10.0k", ref="R84", horizontal=False,
             vpos=(-0.34, -0.14, "right", "center"),
             rpos=(-0.34, 0.16, "right", "center"))
    f.vwire(11.7, 5.68, 5.30)
    gnd(f, 11.7, 5.30)
    f.hwire(u5.pins["R"]["5"][0], 11.7, 7.07)
    f.vwire(u5.pins["R"]["5"][0], 7.07, 8.33)

    # ---- U6 RT8097CHGB → FPGA3.3V ----
    u6 = Chip(f, 5.6, 3.2, 3.0, 2.2, "U6\nRT8097CHGB",
              left=[("4", "VIN", 4.67), ("1", "EN", 3.93)],
              right=[("3", "LX", 4.67), ("5", "FB", 3.93)],
              bottom=[("2", "GND", 7.1)])
    f.hwire(3.2, u6.pins["L"]["4"][0], 4.67)
    f.dot(3.2, 4.67)
    f.hwire(3.2, u6.pins["L"]["1"][0], 3.93)
    f.dot(3.2, 3.93)
    f.vwire(7.1, 3.2, 2.90)
    f.hwire(4.6, 7.1, 2.90)
    gnd(f, 4.6, 2.90)

    f.hwire(u6.pins["R"]["3"][0], 9.85, 4.67)
    ferrite(f, 10.5, 4.67, value="SWPA6028S4R7MT", ref="L3")
    f.hwire(11.15, 16.15, 4.67)
    f.text(13.90, 5.30, "+3.3V (FPGA3.3V)", size=7.4)

    for cx, c in zip((12.7, 13.7, 14.7, 15.7),
                     ("C17 22µF", "C18 4.7µF", "C19 4.7µF", "C20 4.7µF")):
        f.dot(cx, 4.67)
        f.vwire(cx, 4.67, 4.07)
        capacitor(f, cx, 3.41, horizontal=False)
        f.vwire(cx, 2.75, 2.40)
        gnd(f, cx, 2.40)
        f.text(cx - 0.52, 3.41, c, size=6.8, rot=90)

    # L4 隔离 FPGA3.3V 与 3.3V
    ferrite(f, 16.8, 4.67, value="120Ω", ref="L4")
    f.hwire(17.45, 20.0, 4.67)
    f.text(20.2, 4.67, "3.3V", size=8, ha="left", bold=True)
    for cx, c in zip((18.2, 19.1), ("C21 4.7µF", "C22 0.1µF")):
        f.dot(cx, 4.67)
        f.vwire(cx, 4.67, 4.07)
        capacitor(f, cx, 3.41, horizontal=False)
        f.vwire(cx, 2.75, 2.40)
        gnd(f, cx, 2.40)
        f.text(cx - 0.52, 3.41, c, size=6.8, rot=90)

    # U6 FB 分压 R85 / R86
    f.dot(11.7, 4.67)
    f.vwire(11.7, 4.67, 4.07)
    resistor(f, 11.7, 3.41, value="10.0k", ref="R85", horizontal=False,
             vpos=(-0.34, -0.14, "right", "center"),
             rpos=(-0.34, 0.16, "right", "center"))
    f.vwire(11.7, 2.75, 2.67)
    f.dot(11.7, 2.67)
    resistor(f, 11.7, 1.94, value="49.9k", ref="R86", horizontal=False,
             vpos=(-0.34, -0.14, "right", "center"),
             rpos=(-0.34, 0.16, "right", "center"))
    f.vwire(11.7, 1.28, 0.90)
    gnd(f, 11.7, 0.90)
    f.hwire(u6.pins["R"]["5"][0], 11.7, 2.67)
    f.vwire(u6.pins["R"]["5"][0], 2.67, 3.93)

    # ---- U11 LD1117-3.3：5V → OUT_3.3V ----
    u11 = Chip(f, 5.6, -0.6, 2.4, 1.6, "U11\nLD1117-3.3",
               left=[("3", "Vin", 0.47), ("4", "NC", -0.07)],
               right=[("2", "Vout", 0.20)],
               bottom=[("1", "GND", 6.8)], name_size=8.2)
    f.hwire(3.2, u11.pins["L"]["3"][0], 0.47)
    f.dot(3.2, 0.47)
    f.vwire(6.8, -0.6, -0.90)
    gnd(f, 6.8, -0.90)

    f.dot(4.2, 0.47)
    f.vwire(4.2, 0.47, -0.13)
    capacitor(f, 4.2, -0.79, horizontal=False)
    f.vwire(4.2, -1.45, -1.80)
    gnd(f, 4.2, -1.80)
    f.text(4.55, -0.79, "C55 4.7µF", size=6.8, ha="left")

    f.hwire(u11.pins["R"]["2"][0], 13.0, 0.20)
    f.text(13.2, 0.20, "OUT_3.3V", size=8, ha="left", bold=True)
    for cx, c in zip((9.6, 10.8), ("C15 4.7µF", "C16 0.1µF")):
        f.dot(cx, 0.20)
        f.vwire(cx, 0.20, -0.40)
        capacitor(f, cx, -1.06, horizontal=False)
        f.vwire(cx, -1.72, -2.05)
        gnd(f, cx, -2.05)
        f.text(cx - 0.52, -1.06, c, size=6.8, rot=90)

    f.save("fig_power_supply")


# ======================================================================
#  图 2 —— FPGA AS 配置电路
# ======================================================================
def fig_config():
    f = Fig(20.0, 15.6)
    f.text(9.5, 14.55, "FPGA Active Serial Configuration Circuit  (FPGA AS 配置电路)",
           size=12, bold=True)

    # ---- U8 M25P16（信号在右、电源在左）----
    u8 = Chip(f, 2.0, 8.0, 3.0, 5.0, "U8\nM25P16\n(SPI Flash)",
              left=[("8", "VCC", 11.60), ("4", "GND", 10.60),
                    ("3", "WP/IO2", 7.60), ("7", "HOLD/IO3", 6.60)],
              right=[("1", "CS", 11.60), ("6", "CLK", 10.80),
                     ("5", "DI/IO0", 10.00), ("2", "DO/IO1", 9.20)])
    XR8 = u8.pins["R"]["1"][0]      # 5.45

    # ---- FPGA ----
    fp = Chip(f, 9.5, 0.0, 3.2, 13.0, "FPGA EG4S20BG256\n(U7)",
              left=[("T3", "CSO_B", 11.60), ("R11", "CCLK", 10.80),
                    ("T10", "MOSI", 10.00), ("P10", "D0/DIN", 9.20),
                    ("C14", "TCK", 2.60), ("E14", "TDO", 1.80),
                    ("A15", "TMS", 1.00), ("C12", "TDI", 0.20)],
              right=[("R3", "INIT_B", 11.60), ("T2", "PROGRAM_B", 10.60),
                     ("T11", "M0", 9.60), ("P13", "DONE", 8.60),
                     ("N11", "M1", 7.60)],
              name_size=8.4)
    XLF = fp.pins["L"]["T3"][0]     # 9.05
    XRF = fp.pins["R"]["R3"][0]     # 13.15

    # ---- Flash ↔ FPGA 四线 ----
    for pin, y, net in (("1", 11.60, "SPI_CSN"), ("6", 10.80, "FPGA_CCLK"),
                        ("5", 10.00, "FPGA_MOSI"), ("2", 9.20, "FPGA_D0")):
        f.hwire(XR8, XLF, y)
        netlabel(f, (XR8 + XLF) / 2, y, net, size=7.4)

    # ---- U8 电源/地（左引脚）----
    f.hwire(1.0, 1.55, 11.60)
    vcc(f, 1.0, 11.60, "FPGA3.3V")
    f.hwire(1.0, 1.55, 10.60)
    f.vwire(1.0, 10.60, 9.90)
    gnd(f, 1.0, 9.90)

    # ---- WP / HOLD 上拉到 +3.3V ----
    f.hwire(0.60, 1.55, 7.60)
    f.vwire(0.60, 7.60, 4.85)
    resistor(f, 0.60, 4.20, value="2.21k", ref="R95", horizontal=False,
             vpos=(-0.30, -0.16, "right", "center"), rpos=(-0.30, 0.16, "right", "center"))
    f.vwire(0.60, 3.55, 3.20)
    f.dot(0.60, 3.20)
    f.hwire(1.20, 1.55, 6.60)
    f.vwire(1.20, 6.60, 4.85)
    resistor(f, 1.20, 4.20, value="2.21k", ref="R96", horizontal=False,
             vpos=(0.30, -0.16, "left", "center"), rpos=(0.30, 0.16, "left", "center"))
    f.vwire(1.20, 3.55, 3.20)
    f.dot(1.20, 3.20)
    f.hwire(0.60, 2.60, 3.20)
    vcc(f, 2.60, 3.20, "FPGA3.3V")

    # ---- 配置状态：INIT_B / PROGRAM_B / M0 / DONE 上拉，M1 下拉 ----
    for pin, ry, ref, val in (("R3", 11.60, "R89", "10.0k"),
                              ("T2", 10.60, "R91", "10.0k"),
                              ("T11", 9.60, "R92", "470"),
                              ("P13", 8.60, "R90", "10.0k")):
        f.hwire(XRF, 14.40, ry)
        resistor(f, 15.05, ry, value=None, ref=None)
        f.hwire(15.70, 16.60, ry)
        vcc(f, 16.60, ry, "3.3V")
        f.text(15.05, ry + 0.28, f"{ref} {val}", size=6.6, va="bottom")
    f.hwire(XRF, 14.40, 7.60)
    resistor(f, 15.05, 7.60, value=None, ref=None)
    f.hwire(15.70, 16.40, 7.60)
    f.vwire(16.40, 7.60, 7.00)
    gnd(f, 16.40, 7.00)
    f.text(15.05, 7.88, "R93 470", size=6.6, va="bottom")
    f.text(15.05, 7.32, "→ GND", size=6.6, va="top")

    # ---- JTAG ----
    jt = Chip(f, 1.0, 0.0, 2.6, 3.0, "JTAG\n接口",
              right=[("1", "TCK", 2.60), ("2", "TDI", 1.80),
                     ("3", "TMS", 1.00), ("4", "TDO", 0.20)],
              name_size=8.2)
    jmap = [("1", 2.60, "R77", "TCK"), ("4", 1.80, "R78", "TDO"),
            ("3", 1.00, "R76", "TMS"), ("2", 0.20, "R79", "TDI")]
    for num, yy, r, sig in jmap:
        f.hwire(jt.pins["R"][num][0], 6.25, yy)
        resistor(f, 6.90, yy, value=None, ref=None)
        f.hwire(7.55, XLF, yy)
        netlabel(f, 5.10, yy, f"USB_JTAG_{sig}", size=7.0)
        f.text(6.90, yy + 0.26, f"{r} 0Ω", size=6.6, va="bottom")
    f.text(5.10, 3.55, "R76–R79 为 0Ω 串接电阻", size=7.0, ha="center")

    f.save("fig_config_circuit")


# ======================================================================
#  图 3 —— 时钟电路
# ======================================================================
def fig_clock():
    f = Fig(14.0, 5.6)
    f.text(7.4, 5.25, "FPGA Clock Circuit  (FPGA 时钟电路)", size=12, bold=True)

    y3 = Chip(f, 3.0, 1.6, 3.2, 2.4, "Y3\n7X-50.000MBB-T\n50 MHz 有源晶振",
              left=[("1", "E/C", 3.20), ("2", "GND", 2.40)],
              right=[("3", "OUT", 3.20), ("4", "VDD", 2.40)],
              name_size=8.2)

    f.hwire(1.0, y3.pins["L"]["1"][0], 3.20)
    vcc(f, 1.0, 3.20, "3.3V")
    f.hwire(1.6, y3.pins["L"]["2"][0], 2.40)
    f.vwire(1.6, 2.40, 1.50)
    gnd(f, 1.6, 1.50)

    # pin3 OUT -> R97 -> FPGA_GCLK1
    f.hwire(y3.pins["R"]["3"][0], 8.10, 3.20)
    resistor(f, 8.75, 3.20, value=None, ref=None)
    f.hwire(9.40, 10.75, 3.20)
    netlabel(f, 10.05, 3.20, "FPGA_GCLK1", size=7.2)
    f.text(8.75, 3.44, "R97  22.1Ω", size=6.8, va="bottom")
    Chip(f, 11.20, 1.60, 2.20, 1.60, "FPGA\n(U7C)",
         left=[("T8", "GCLK1")], name_size=8.2)

    # pin4 VDD -> 3.3V + C35（向下引出）
    f.hwire(y3.pins["R"]["4"][0], 8.30, 2.40)
    f.dot(6.90, 2.40)
    ct, cb = capacitor(f, 6.90, 1.14, horizontal=False)
    f.vwire(6.90, 2.40, ct[1])
    f.vwire(6.90, cb[1], 0.15)
    gnd(f, 6.90, 0.15)
    f.text(7.25, 1.14, "C35 0.1µF", size=6.8, ha="left")
    vcc(f, 8.30, 2.40, "3.3V")

    f.save("fig_clock_circuit")


# ======================================================================
#  图 4 —— 外设接口
# ======================================================================
def fig_peripheral():
    f = Fig(22.0, 18.4)

    # ================= 上：UART =================
    f.text(0.4, 17.75, "UART（USB 转串口，CH340N）", size=10, ha="left", bold=True)
    usb = Chip(f, 0.4, 15.0, 1.6, 1.2, "Micro\nUSB",
               right=[("1", "D+", 15.90), ("2", "D-", 15.10)], name_size=7.4)
    u2 = Chip(f, 3.6, 13.4, 3.0, 3.2, "U2\nCH340N",
              left=[("1", "UD+", 15.90), ("2", "UD-", 15.10),
                    ("3", "GND", 14.30), ("4", "RTS#", 13.50)],
              right=[("5", "VCC", 15.90), ("6", "TXD", 15.10),
                     ("7", "RXD", 14.30), ("8", "V3", 13.50)],
              name_size=8.6)
    f.hwire(usb.pins["R"]["1"][0], u2.pins["L"]["1"][0], 15.90)
    f.hwire(usb.pins["R"]["2"][0], u2.pins["L"]["2"][0], 15.10)
    f.hwire(2.60, u2.pins["L"]["3"][0], 14.30)
    f.vwire(2.60, 14.30, 13.60)
    gnd(f, 2.60, 13.60)

    f.hwire(u2.pins["R"]["5"][0], 8.20, 15.90)
    vcc(f, 8.20, 15.90, "3.3V")
    f.hwire(u2.pins["R"]["8"][0], 8.60, 13.50)
    f.dot(8.20, 13.50)
    ct, cb = capacitor(f, 8.20, 12.54, horizontal=False)
    f.vwire(8.20, 13.50, ct[1])
    f.vwire(8.20, cb[1], 11.55)
    gnd(f, 8.20, 11.55)
    f.text(8.55, 12.54, "C2 0.1µF", size=6.8, ha="left")

    fpga_u = Chip(f, 11.0, 13.4, 2.8, 3.2, "FPGA EG4S20BG256",
                  left=[("F12", "RXD", 15.10), ("D12", "TXD", 14.30)],
                  name_size=8.2)
    f.hwire(u2.pins["R"]["6"][0], fpga_u.pins["L"]["F12"][0], 15.10)
    netlabel(f, 9.6, 15.10, "网 RXD", size=7.4)
    f.hwire(u2.pins["R"]["7"][0], fpga_u.pins["L"]["D12"][0], 14.30)
    netlabel(f, 9.6, 14.30, "网 TXD", size=7.4)

    # ================= 中：JTAG 调试 / 仿真器 =================
    f.text(0.4, 10.75, "JTAG 调试 / 仿真器（GD32F150G8U6）", size=10, ha="left", bold=True)
    fpga_j = Chip(f, 0.8, 5.4, 2.4, 4.8, "FPGA\nEG4S20BG256",
                  right=[("C14", "TCK", 9.50), ("A15", "TMS", 8.80),
                         ("C12", "TDI", 8.10), ("E14", "TDO", 7.40),
                         ("C13", "UART_TX", 6.70), ("E12", "UART_RX", 6.00)],
                  name_size=8.0)
    XRJ = fpga_j.pins["R"]["C14"][0]        # 3.65

    # FPGA JTAG 引脚 → R76–R79（0Ω）→ USB_JTAG_* 网络
    for num, yy, r, sig in (("C14", 9.50, "R77", "TCK"),
                            ("A15", 8.80, "R76", "TMS"),
                            ("C12", 8.10, "R79", "TDI"),
                            ("E14", 7.40, "R78", "TDO")):
        f.hwire(XRJ, 5.35, yy)
        resistor(f, 6.00, yy, value=None, ref=None)
        f.hwire(6.65, 8.30, yy)
        netlabel(f, 8.45, yy, f"USB_JTAG_{sig}", size=7.0, ha="left")
        f.text(6.00, yy + 0.26, f"{r} 0Ω", size=6.6, va="bottom")

    # GD32 仿真器：USART0 → FPGA；USB → R66/R67
    u4 = Chip(f, 14.0, 5.0, 3.6, 3.4, "U4\nGD32F150G8U6\n(USB-JTAG 仿真器)",
              left=[("17", "PA9", 6.70), ("18", "PA10", 6.00)],
              right=[("19", "PA11", 6.70), ("20", "PA12", 6.00)],
              name_size=8.0)
    XGL = u4.pins["L"]["17"][0]             # 13.55
    for fpin, ry, num, r in (("C13", 6.70, "17", "R71"),
                             ("E12", 6.00, "18", "R70")):
        f.hwire(XRJ, 7.35, ry)
        resistor(f, 8.00, ry, value=None, ref=None)
        f.hwire(8.65, XGL, ry)
        f.text(8.00, ry + 0.26, f"{r} 0Ω", size=6.6, va="bottom")
    for num, yy, ref, val, net in (("20", 6.00, "R66", "22.1Ω", "USB_D+"),
                                   ("19", 6.70, "R67", "22.1Ω", "USB_D-")):
        f.hwire(u4.pins["R"][num][0], 18.05, yy)
        resistor(f, 18.70, yy, value=None, ref=None)
        f.hwire(19.35, 20.30, yy)
        netlabel(f, 20.50, yy, net, size=7.0, ha="left")
        f.text(18.70, yy + 0.26, f"{ref} {val}", size=6.6, va="bottom")

    # ================= 下：DAC =================
    f.text(0.4, 4.75, "DAC（R-2R 电阻网络 + 运放）", size=10, ha="left", bold=True)
    led = ["B14", "B15", "B16", "C15", "C16", "E13", "E16", "F16"]
    ys = [3.45 - 0.44 * i for i in range(8)]
    dac = Chip(f, 1.0, -0.80, 2.8, 5.00, "FPGA led[0..7]",
               right=[(led[i], f"led[{i}]", ys[i]) for i in range(8)],
               name_size=8.2)
    for i in range(8):
        f.hwire(dac.pins["R"][led[i]][0], 5.35, ys[i])
        resistor(f, 6.00, ys[i], value=None, ref=None)
        f.hwire(6.65, 7.40, ys[i])
        f.text(4.80, ys[i] + 0.13, f"R{i + 46} 20.0k", size=6.0, va="bottom")
    f.rect(7.40, -0.80, 1.8, 5.00)
    f.text(8.30, 1.70, "R-2R 网络\nR56–R62", size=7.2)
    f.hwire(9.20, 10.25, 1.70)
    resistor(f, 10.90, 1.70, value="1.00k", ref="R45")

    op = Chip(f, 13.40, 0.10, 2.4, 2.4, "U1\nSGM321",
              left=[("3", "IN+", 2.10), ("4", "IN-", 1.30)],
              right=[("1", "OUT", 1.70)],
              top=[("5", "V+", 14.60)], bottom=[("2", "V-", 14.60)],
              name_size=8.2)
    f.hwire(11.55, op.pins["L"]["3"][0], 2.10)
    f.vwire(11.85, -1.30, 1.30)
    f.hwire(11.85, op.pins["L"]["4"][0], 1.30)
    f.hwire(11.85, 16.20, -1.30)
    f.vwire(16.20, -1.30, 1.70)
    f.dot(16.20, 1.70)
    f.hwire(op.pins["R"]["1"][0], 17.15, 1.70)
    netlabel(f, 16.60, 1.70, "DAC_VOUT", size=7.2)

    f.vwire(op.pins["T"]["5"][0], op.pins["T"]["5"][1], 4.36)
    f.dot(14.60, 4.36)
    vcc(f, 14.60, 4.36, "3.3V")
    f.hwire(12.40, 14.60, 4.36)
    capacitor(f, 12.40, 3.70, horizontal=False)
    f.vwire(12.40, 3.04, 2.80)
    gnd(f, 12.40, 2.80)
    f.text(11.78, 3.70, "C1 0.1µF", size=6.8, ha="right")
    f.vwire(op.pins["B"]["2"][0], op.pins["B"]["2"][1], -0.60)
    gnd(f, 14.60, -0.60)

    j1 = Chip(f, 17.60, 0.70, 1.5, 2.0, "J1",
              left=[("1", "1", 1.70), ("2", "2", 1.00)], name_size=7.6)
    f.hwire(op.pins["R"]["1"][0], j1.pins["L"]["1"][0], 1.70)
    f.hwire(16.90, j1.pins["L"]["2"][0], 1.00)
    f.vwire(16.90, 1.00, 0.40)
    gnd(f, 16.90, 0.40)

    f.save("fig_peripheral")


if __name__ == "__main__":
    print("=== 生成黑白原理图 ===")
    fig_power()
    fig_config()
    fig_clock()
    fig_peripheral()
    print("完成：", OUT)
