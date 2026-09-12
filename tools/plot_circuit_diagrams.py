# -*- coding: utf-8 -*-
"""
plot_circuit_diagrams.py
第三节(一)仿真电路 —— 7 张 RTL 电路图（据 rtl/*.v 真实结构绘制）

fig11 系统仿真总图（验证架构）
fig12 运动控制闭环电路
fig13 ES8388/I2S 音频接口电路（含跨时钟域）
fig14 MFCC 特征提取数据通路电路
fig15 声纹认证与段级决策电路
fig16 命令识别电路
fig17 联合决策 + 双麦方向感知电路

绘图风格：标准 RTL 原理图/数据通路框图。所有模块名、端口名、位宽、参数
均取自仓库内 rtl/*.v 与顶层参数，不编造信号。
"""
import math
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon

# ---------------- 全局样式 ----------------
plt.rcParams["font.family"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

C_MOD   = "#E8F1FB"   # 模块（浅蓝）
C_EDGE  = "#1F5AA5"
C_STORE = "#FBF3D9"   # 存储/参数（浅琥珀）
C_STORE_E = "#B08500"
C_OP    = "#E3F1E3"   # 组合运算（浅绿）
C_OP_E  = "#2E7D32"
C_DEC   = "#FBE4E4"   # 决策/判决（浅珊瑚）
C_DEC_E = "#B3372C"
C_IO    = "#F2EDE8"   # 输入输出/外设（浅灰）
C_IO_E  = "#6B6B6B"
C_LEG   = "#EDEDED"   # 已弃用/对照（灰）
C_LEG_E = "#9E9E9E"
C_TXT   = "#222222"
C_SUB   = "#444444"
C_LINE  = "#333333"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def canvas(w=100, h=56):
    """新建等比例画布，返回 (fig, ax)。"""
    fig, ax = plt.subplots(figsize=(w / 7.0, h / 7.0), dpi=150)
    ax.set_xlim(0, w)
    ax.set_ylim(0, h)
    ax.axis("off")
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    return fig, ax


def rbox(ax, x, y, w, h, title, sub=None, fc=C_MOD, ec=C_EDGE, lw=1.5,
         tfs=8.5, sfs=7.0, hatch=None, z=3, tcolor=C_TXT, scolor=C_SUB):
    """矩形模块框：标题(粗)在上，说明(小)在下；sub 可含 \\n。"""
    ax.add_patch(Rectangle((x, y), w, h, fc=fc, ec=ec, lw=lw, zorder=z,
                           hatch=hatch))
    cx, cy = x + w / 2.0, y + h / 2.0
    if sub is None:
        ax.text(cx, cy, title, ha="center", va="center", fontsize=tfs,
                color=tcolor, zorder=z + 1, fontweight="bold")
    else:
        ax.text(cx, cy + h * 0.24, title, ha="center", va="center", fontsize=tfs,
                color=tcolor, zorder=z + 1, fontweight="bold")
        ax.text(cx, cy - h * 0.20, sub, ha="center", va="center", fontsize=sfs,
                color=scolor, zorder=z + 1, linespacing=1.35)


def dom_frame(ax, x, y, w, h, label, fs=8.5):
    """时钟域 / 环境虚线框（带左上角标题）。"""
    ax.add_patch(Rectangle((x, y), w, h, fc="#FAFAFA", ec="#999999",
                           lw=1.2, ls="--", zorder=1))
    ax.text(x + 1.2, y + h - 0.6, label, ha="left", va="top", fontsize=fs,
            color="#555555", zorder=2, fontweight="bold")


def _head(ax, p0, p1, color, size=1.7):
    """在 p0->p1 末端画三角箭头。"""
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    tri = Polygon([
        (p1[0], p1[1]),
        (p1[0] - size * math.cos(ang - 0.42), p1[1] - size * math.sin(ang - 0.42)),
        (p1[0] - size * math.cos(ang + 0.42), p1[1] - size * math.sin(ang + 0.42)),
    ], fc=color, ec="none", zorder=5)
    ax.add_patch(tri)


def elbow(ax, pts, label=None, color=C_LINE, lw=1.5, ls="-", fs=7.0,
          lw_label=0.0, label_off=1.3):
    """折线箭头：pts 为 [(x0,y0),...]，终点带箭头。label 放在最后一段中点法线侧。"""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    ax.plot(xs, ys, color=color, lw=lw, ls=ls, zorder=4, solid_capstyle="round")
    _head(ax, pts[-2], pts[-1], color)
    if label is not None:
        x0, y0 = pts[-2]
        x1, y1 = pts[-1]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1e-9
        nx, ny = -dy / L, dx / L          # 法线：水平向右→上方；竖直向上→左侧
        if nx > 0.5 and ny > 0.5:          # 对角向右上时放到左上
            mx, my = (x0 + x1) / 2 - nx * label_off, (y0 + y1) / 2 + ny * label_off
        else:
            mx, my = (x0 + x1) / 2 + nx * label_off, (y0 + y1) / 2 + ny * label_off
        ax.text(mx, my, label, ha="center", va="center", fontsize=fs, color=color,
                zorder=6, bbox=dict(fc="white", ec="none", alpha=0.85, pad=0.4))


def save(fig, name):
    path = os.path.join(ROOT, name)
    fig.savefig(path, bbox_inches="tight", pad_inches=0.08, dpi=150)
    plt.close(fig)
    print("OK", name, "%.0fx%.0f" % (fig.get_size_inches()[0] * 150,
                                     fig.get_size_inches()[1] * 150))
    return path


# =====================================================================
# fig11 系统仿真总图（验证架构）
# =====================================================================
def fig11():
    fig, ax = canvas(100, 56)

    # ---- 顶部流水：参考→向量→仿真→比对 ----
    rbox(ax, 1, 46, 20, 7, "Python Golden 参考模型",
         "py/audio_golden.py\npy/gen_*.py", fc=C_OP)
    rbox(ax, 22, 46, 20, 7, "测试向量",
         ".mem / 参数内嵌\n(模板·窗·dct基)", fc=C_STORE, ec=C_STORE_E)
    rbox(ax, 44, 46, 28, 7, "ModelSim 仿真（整链）",
         "vsim 10.3c · sim/*.do · 被测设计 DUT", fc=C_MOD)
    rbox(ax, 76, 46, 23, 7, "逐位比对结果",
         "PASS/FAIL\nmax|diff|=0（16帧×13维）", fc=C_DEC, ec=C_DEC_E)
    elbow(ax, [(21, 49.5), (22, 49.5)], label="生成", lw=1.2)
    elbow(ax, [(42, 49.5), (44, 49.5)], label="激励+期望", lw=1.2)
    elbow(ax, [(72, 49.5), (76, 49.5)], label="RTL 输出 vs 期望", lw=1.2)

    # ---- 中部：ModelSim 环境展开 ----
    dom_frame(ax, 42, 10, 40, 32, "ModelSim 仿真环境（sim/audio_sim）")
    rbox(ax, 46, 34, 32, 5, "Testbench tb_*.v",
         "激励施加 + 时钟/复位 + 逐位比对", fc=C_IO, ec=C_IO_E, tfs=8, sfs=6.8)
    rbox(ax, 46, 13, 32, 17, "被测设计 DUT：top_voice_robot.v（整链）",
         None, fc=C_MOD, lw=1.8, tfs=8.5)
    rbox(ax, 50, 23, 24, 4.6, "① 语音感知链",
         "audio_pcm_bridge→audio_vad→v2_frame_ctrl→\nfeature_engine→seg_decide（+dir_energy）",
         fc=C_MOD, tfs=7.8, sfs=6.2)
    rbox(ax, 50, 17.5, 24, 4.0, "② 运动控制链",
         "state_machine→trajectory_planner→\npid_controller→virtual_motor",
         fc=C_MOD, tfs=7.8, sfs=6.2)
    rbox(ax, 50, 13.2, 24, 3.4, "③ 输出与外设",
         "uart_telemetry[AA]·seven_seg·led·beep·keypad",
         fc=C_MOD, tfs=7.8, sfs=6.2)
    elbow(ax, [(62, 34), (62, 30)], label="clk/rst/激励", lw=1.2)

    # ---- 底部：板上真实采集路径 ----
    rbox(ax, 1, 2, 40, 7, "板上真实采集路径",
         "ES8388→FPGA 整链→UART [AA]/[AB] 遥测→PC 离线复算",
         fc=C_LEG, ec=C_LEG_E, hatch="///")
    rbox(ax, 58, 2, 30, 6, "真实帧送入 RTL 比对",
         "fe_real.mem（replay_pcm 16 帧×13 维）",
         fc=C_LEG, ec=C_LEG_E, hatch="///")
    elbow(ax, [(11, 9), (11, 46)], label="真实录音 48k PCM（离线 Golden/阈值定标/绘图）", lw=1.3, color="#777777")
    elbow(ax, [(58, 8), (44, 8), (44, 36.5), (46, 36.5)], label="真实帧", lw=1.3, color="#777777")

    return save(fig, "fig11_sim_arch.png")


# =====================================================================
# fig12 运动控制闭环电路
# =====================================================================
def fig12():
    fig, ax = canvas(100, 56)

    ax.text(50, 55.4, "clk 50MHz · tick_1ms clock-enable · 同步复位 rst_n",
            ha="center", fontsize=7.5, color="#666666")

    rbox(ax, 1, 42, 22, 6, "目标源",
         "键盘 target_input / 语音 seam\nvgoal → target·go", fc=C_IO, ec=C_IO_E)
    rbox(ax, 1, 20, 22, 15, "state_machine 运行状态机",
         "IDLE·READY·MOVE·HOLD·FAULT\nmoving=MOVE · faulted=FAULT\n任意态 fault→FAULT，ack→IDLE",
         fc=C_MOD, sfs=6.8)
    rbox(ax, 1, 6, 22, 5, "故障源",
         "fault_detector · SW2（演示）", fc=C_LEG, ec=C_LEG_E, hatch="///")

    rbox(ax, 33, 44, 26, 9, "trajectory_planner 梯形限速",
         "ref 定点 deg<<8；每 tick ±STEP(≈38)\nen 上升沿从 pos0 起算", fc=C_OP, ec=C_OP_E)
    rbox(ax, 66, 44, 26, 9, "pid_controller 位置环 PID",
         "err 限幅 ±180；KP=2048\n(P·err+I·acc+D·derr)>>10；输出 ±61440", fc=C_OP, ec=C_OP_E)
    rbox(ax, 66, 28, 26, 9, "virtual_motor 虚拟电机",
         "pos 定点<<10 积分；一阶逼近\nTAU=100ms；限位 [0,180]°", fc=C_OP, ec=C_OP_E)
    rbox(ax, 33, 28, 26, 8, "到位比较器",
         "dev = |pos − target|\nat_target = (dev ≤ 2)", fc=C_DEC, ec=C_DEC_E)
    rbox(ax, 66, 8, 26, 6, "外设输出",
         "seven_seg·led·beep\nuart_telemetry → [AA]", fc=C_IO, ec=C_IO_E)

    elbow(ax, [(12, 42), (12, 35)], label="target_valid / start")
    elbow(ax, [(23, 31), (33, 48.5)], label="moving (en)")
    elbow(ax, [(59, 48.5), (66, 48.5)], label="ref_pos[9:0]")
    elbow(ax, [(79, 44), (79, 37)], label="cmd[19:0]\n(度/秒×1024)")
    elbow(ax, [(92, 37), (92, 44)], label="pos 反馈", color="#1F5AA5")
    elbow(ax, [(66, 32.5), (59, 32)], label="pos[9:0]")
    elbow(ax, [(33, 31), (23, 29)], label="at_target")
    elbow(ax, [(12, 11), (12, 20)], label="fault_in")
    elbow(ax, [(23, 45), (33, 36.5)], label="target[9:0]")
    elbow(ax, [(79, 28), (79, 14)], label="pos→显示/遥测")

    return save(fig, "fig12_motion_ctrl_circuit.png")


# =====================================================================
# fig13 ES8388 / I2S 音频接口电路（跨时钟域）
# =====================================================================
def fig13():
    fig, ax = canvas(100, 56)

    rbox(ax, 1, 48, 22, 7, "PLL clk_wiz_0",
         "clk0→50MHz；clk1→aud_mclk 12.3MHz\nlocked → 音频复位 rst_i", fc=C_IO, ec=C_IO_E, sfs=6.5)
    rbox(ax, 76, 48, 23, 7, "I2C 配置 es8388_config",
         "addr 0x11 · ADC 输入 IN1(咪头)\naud_scl / aud_sda", fc=C_IO, ec=C_IO_E, sfs=6.5)
    rbox(ax, 33, 46, 32, 9, "ES8388 音频编解码器（ADC）",
         "MIC→24bit ADC；产生 BCLK/LRCK/SD_M\nMCLK 由 FPGA PLL 供给（MCLK=256×fs）",
         fc=C_MOD, sfs=6.5)

    dom_frame(ax, 3, 12, 44, 30, "aud_bclk 域（≈2.304 MHz）")
    rbox(ax, 7, 34, 36, 4.6, "LRC 沿检测", "aud_lrc 跳变 → 字起始·判声道",
         fc=C_OP, ec=C_OP_E, tfs=7.8, sfs=6.3)
    rbox(ax, 7, 26, 36, 4.6, "I2S 移位接收 wd_buf",
         "MSB 先行收 WL=24bit；rx_cnt 计数", fc=C_OP, ec=C_OP_E, tfs=7.8, sfs=6.3)
    rbox(ax, 7, 18, 36, 4.6, "声道分离缓冲",
         "第 2/4…字提交 pcm_l_t / pcm_r_t", fc=C_OP, ec=C_OP_E, tfs=7.8, sfs=6.3)
    rbox(ax, 7, 12.4, 36, 3.6, "pair_tgl 翻转握手",
         "数据稳定后再翻转（滞后 1 拍）", fc=C_STORE, ec=C_STORE_E, tfs=7.8, sfs=6.3)

    dom_frame(ax, 55, 12, 44, 30, "sys_clk 域（50 MHz）")
    rbox(ax, 59, 30, 36, 5, "2 级触发器同步",
         "tgl_s1→tgl_s2→tgl_s3（异步复位同步化）", fc=C_OP, ec=C_OP_E, tfs=7.8, sfs=6.3)
    rbox(ax, 59, 22, 36, 4.6, "沿检测",
         "pair_valid = tgl_s2 ^ tgl_s3（≈48kHz）", fc=C_OP, ec=C_OP_E, tfs=7.8, sfs=6.3)
    rbox(ax, 59, 14, 36, 4.6, "跨域锁存 PCM",
         "沿上锁存 pcm_l / pcm_r[23:0]", fc=C_STORE, ec=C_STORE_E, tfs=7.8, sfs=6.3)

    elbow(ax, [(40, 46), (40, 42.5)], label="BCLK / LRCK / SD_M（I2S）")
    elbow(ax, [(23, 51.5), (33, 51.5)], label="aud_mclk 12.3MHz")
    elbow(ax, [(76, 51.5), (65, 51.5)], label="I2C SCL/SDA")
    elbow(ax, [(43, 14.2), (59, 30)], label="pair_tgl 跨域握手（电平翻转）", color="#1F5AA5")
    elbow(ax, [(77, 14), (77, 9)], label="pcm_l/r + pair_valid")

    rbox(ax, 55, 2, 44, 7, "audio_vad 峰值能量 VAD",
         "窗能量→LED；TH_ON/TH_OFF 滞回；HO=32 帧拖尾 → vad_on",
         fc=C_DEC, ec=C_DEC_E, tfs=8, sfs=6.5)
    ax.text(3, 8.5, "rst_i = rst_n & locked；audio_rst_n = rst_i & init_done(INIT_MS=200ms)",
            ha="left", va="center", fontsize=6.3, color="#666666")

    return save(fig, "fig13_audio_if_circuit.png")


# =====================================================================
# fig14 MFCC 特征提取数据通路电路
# =====================================================================
def fig14():
    fig, ax = canvas(100, 56)

    rbox(ax, 1, 45, 24, 7, "v2_frame_ctrl 帧控制器",
         "VAD 门控开帧；每帧 64 采样\nframe_start + pcm 流", fc=C_IO, ec=C_IO_E, sfs=6.5)
    rbox(ax, 27, 45, 16, 9, "pre_emph 预加重",
         "y = x − a·x[n−1]\nQ14：a≈0.97(15892/2¹⁴)", fc=C_OP, ec=C_OP_E)
    rbox(ax, 45, 45, 17, 9, "front_wind 分帧+Hann窗",
         "N=64 单缓冲\nQ15：round(x·w+2¹⁴)>>15", fc=C_OP, ec=C_OP_E)
    rbox(ax, 64, 45, 18, 9, "fft_core radix-2 DIT",
         "N=64；Q15 旋转因子\n块RAM 64×32；逐级 >>1", fc=C_OP, ec=C_OP_E)
    rbox(ax, 84, 45, 15, 9, "功率谱",
         "(re²+im²) >> 22\npowr[0..32]", fc=C_OP, ec=C_OP_E, sfs=6.6)

    rbox(ax, 27, 28, 16, 9, "mel_bank Mel滤波",
         "20 三角滤波器\nQ12 加权求和", fc=C_OP, ec=C_OP_E)
    rbox(ax, 45, 28, 17, 9, "log2_lut 对数",
         "20 维 log-mel\n定点 Q8.6 查表", fc=C_OP, ec=C_OP_E)
    rbox(ax, 64, 28, 18, 9, "dct2_mfcc DCT-II",
         "基矩阵 b[k][m] Q12\n取前 13 维系数", fc=C_OP, ec=C_OP_E)
    rbox(ax, 84, 28, 15, 9, "特征输出",
         "feature_data[15:0]\nfeature_index[3:0]\nfeature_valid", fc=C_STORE, ec=C_STORE_E, sfs=6.4)

    rbox(ax, 1, 16, 24, 6, "内部存储",
         "win[0:63] 窗缓冲\npowr[0:32] 功率 bin\nlm20[0:19] log-mel", fc=C_STORE, ec=C_STORE_E, tfs=7.2, sfs=6.0)

    rbox(ax, 27, 2, 72, 6, "feature_engine 流水线控制器（FSM）",
         "WAIT→CAPT→WIN→FFTLOAD→FFT/POWER→MELFEED→LOGOUT→DCTLOAD→DCT→DONE",
         fc=C_LEG, ec=C_LEG_E, tfs=7.8, sfs=6.4)

    elbow(ax, [(25, 48.5), (27, 48.5)], label="pcm[23:0]")
    elbow(ax, [(43, 49.5), (45, 49.5)], label="24bit")
    elbow(ax, [(62, 49.5), (64, 49.5)], label="窗值帧")
    elbow(ax, [(82, 49.5), (84, 49.5)], label="re/im 32bit")
    elbow(ax, [(91.5, 45), (35, 37)], label="33 个功率 bin")
    elbow(ax, [(43, 32.5), (45, 32.5)], label="mel[63:0] Q12")
    elbow(ax, [(62, 32.5), (64, 32.5)], label="log-mel 16bit")
    elbow(ax, [(82, 32.5), (84, 32.5)], label="int16×13")
    elbow(ax, [(12, 45), (12, 8), (27, 5)], label="frame_start / enable", color="#777777", lw=1.2)

    ax.text(2, 53, "sys_clk 50MHz 单一时钟域 · 每级 1 拍流水 · 有符号定点中间量",
            ha="left", fontsize=6.3, color="#666666")

    return save(fig, "fig14_mfcc_circuit.png")


# =====================================================================
# fig15 声纹认证与段级决策电路
# =====================================================================
def fig15():
    fig, ax = canvas(100, 56)

    rbox(ax, 1, 44, 24, 8, "feature_engine 特征输出",
         "fe_valid · fe_index[3:0]\nfe_data[15:0]（13 维逐维）", fc=C_IO, ec=C_IO_E, sfs=6.6)
    rbox(ax, 1, 32, 24, 8, "audio_vad",
         "vad / vad_rise / vad_fall\n（段电平 + 沿）", fc=C_IO, ec=C_IO_E, sfs=6.6)

    rbox(ax, 30, 44, 32, 8, "段内累加器",
         "仅 vad 帧：sum[d] += fe_data\n（13×32bit）+ cnt；vad_rise 清零", fc=C_OP, ec=C_OP_E)
    rbox(ax, 66, 44, 32, 8, "段末判决 FSM",
         "S_ACC→LAT→CALC→DIV0→DIV→FIN\n逐维 |sum[d] − cnt·T[d]|（5 模板并行）", fc=C_MOD, sfs=6.6)
    rbox(ax, 30, 32, 32, 8, "模板 ROM（参数内嵌 208bit）",
         "TPL_V owner · TPL_0 stop · TPL_1 left\nTPL_2 right · TPL_3 forward", fc=C_STORE, ec=C_STORE_E, sfs=6.6)
    rbox(ax, 66, 32, 32, 8, "无除法判决",
         "owner：acc_v < cnt·TH_OWN(4300)\ncmd ：argmin(acc0..3) → cmd_id\n(S_DIV 恢复除法仅调试 own_mean)",
         fc=C_DEC, ec=C_DEC_E, sfs=6.4)
    rbox(ax, 66, 18, 32, 8, "段末输出",
         "owner_valid（段末电平）· seg_done（单拍）\ncmd_id[1:0]（0停 1左 2右 3前）", fc=C_IO, ec=C_IO_E, sfs=6.6)

    elbow(ax, [(25, 48), (30, 48)], label="13 维逐维")
    elbow(ax, [(62, 48), (66, 48)], label="sum[0..12], cnt")
    elbow(ax, [(82, 44), (82, 40)], label="acc_v / acc0..3")
    elbow(ax, [(82, 32), (82, 26)], label="判决")
    elbow(ax, [(13, 40), (32, 44)], label="vad / rise / fall")
    elbow(ax, [(62, 36), (66, 44)], label="cnt·T[d]")
    elbow(ax, [(24, 44), (28, 44), (28, 11), (34, 11)],
          label="（对照）", color="#888888", lw=1.2, ls="--")

    rbox(ax, 30, 2, 68, 9, "已弃用的逐帧对照路径",
         "speaker_verify/vtmpl：L1 距离 dist≤TH（逐帧）  →  utter_vote：段内匹配累计 ≥ MIN_MATCH=5",
         fc=C_LEG, ec=C_LEG_E, hatch="///", tfs=7.8, sfs=6.4)
    ax.text(62, 12.8, "逐帧 owner/stranger 距离重叠（3584~7424）不可分 → 由段级决策替代",
            ha="center", fontsize=6.4, color="#777777")

    return save(fig, "fig15_seg_circuit.png")


# =====================================================================
# fig16 命令识别电路
# =====================================================================
def fig16():
    fig, ax = canvas(100, 56)

    rbox(ax, 1, 40, 24, 8, "feature_engine 特征",
         "mfcc_valid · mfcc_data[15:0]\n（13 维逐维）", fc=C_IO, ec=C_IO_E, sfs=6.6)

    rbox(ax, 30, 46, 26, 6, "vtmpl #0 — TPL0 stop",
         "L1：Σ|x[i]−t[i]| 逐维累加 DIM=13", fc=C_MOD, tfs=7.6, sfs=6.2)
    rbox(ax, 30, 38, 26, 6, "vtmpl #1 — TPL1 left",
         "L1：Σ|x[i]−t[i]| 逐维累加 DIM=13", fc=C_MOD, tfs=7.6, sfs=6.2)
    rbox(ax, 30, 30, 26, 6, "vtmpl #2 — TPL2 right",
         "L1：Σ|x[i]−t[i]| 逐维累加 DIM=13", fc=C_MOD, tfs=7.6, sfs=6.2)
    rbox(ax, 30, 22, 26, 6, "vtmpl #3 — TPL3 forward",
         "L1：Σ|x[i]−t[i]| 逐维累加 DIM=13", fc=C_MOD, tfs=7.6, sfs=6.2)

    rbox(ax, 58, 36, 24, 8, "比较树（argmin）",
         "以 d0 为基准逐级比较\n→ cmd_id（0停1左2右3前）", fc=C_DEC, ec=C_DEC_E, sfs=6.6)
    rbox(ax, 84, 36, 15, 8, "cmd_vote 窗口投票",
         "滑动 VOTE_N=8 众数\n并列取小 id", fc=C_MOD, sfs=6.5)
    rbox(ax, 84, 22, 15, 7, "输出",
         "decision_valid\ncmd_id_out", fc=C_IO, ec=C_IO_E, sfs=6.5)

    elbow(ax, [(25, 48), (30, 49)], label="13 维逐维", lw=1.2)
    elbow(ax, [(25, 44), (30, 41)], lw=1.2)
    elbow(ax, [(25, 40), (30, 33)], lw=1.2)
    elbow(ax, [(25, 36), (30, 25)], lw=1.2)
    elbow(ax, [(56, 49), (58, 40)], lw=1.2)
    elbow(ax, [(56, 41), (58, 40)], lw=1.2)
    elbow(ax, [(56, 33), (58, 40)], lw=1.2)
    elbow(ax, [(56, 25), (58, 40)], lw=1.2)
    ax.text(57.2, 43.2, "d0..d3", ha="center", fontsize=6.3, color="#333333")
    elbow(ax, [(82, 40), (84, 39.5)], label="cmd_id", lw=1.2)
    elbow(ax, [(91.5, 36), (91.5, 29)], label="decision", lw=1.2)

    ax.text(2, 55, "模板 TPL0..3 由 data/commands/cmd_{stop,left,right,forward}.mem 生成，参数内嵌",
            ha="left", fontsize=6.3, color="#666666")
    ax.text(50, 1.5,
            "说明：当前顶层整词段级决策改走 seg_decide 的段级 argmin（图15）；本 cmd_matcher/cmd_vote 为逐帧 KWS 路径，"
            "仍由 tb_cmd_matcher / tb_cmd_vote 覆盖验证。",
            ha="center", fontsize=6.5, color="#777777")

    return save(fig, "fig16_cmd_circuit.png")


# =====================================================================
# fig17 联合决策 + 双麦方向感知电路
# =====================================================================
def fig17():
    fig, ax = canvas(100, 56)

    # ---- 左：dir_energy ----
    rbox(ax, 1, 44, 24, 7, "audio_pcm_bridge",
         "pcm_l[23:0] · pcm_r[23:0]\nsample_ok（≈48k）", fc=C_IO, ec=C_IO_E, sfs=6.4)
    rbox(ax, 1, 36, 24, 6, "audio_vad",
         "vad / vad_rise / vad_fall", fc=C_IO, ec=C_IO_E, sfs=6.4)
    rbox(ax, 30, 44, 18, 7, "取模与段内累加",
         "Σ|pcm_l| · Σ|pcm_r|（48bit）\nvad_rise 清零", fc=C_OP, ec=C_OP_E, sfs=6.4)
    rbox(ax, 30, 32, 18, 8, "交叉相乘方向判决",
         "SL·21 > SR·20 → 左\nSR·21 > SL·20 → 右\n否则 → 中（无除法）", fc=C_DEC, ec=C_DEC_E, sfs=6.2)
    rbox(ax, 30, 22, 18, 6, "方向输出",
         "dir[1:0] 段末锁存\n0中 / 1左 / 2右", fc=C_IO, ec=C_IO_E, sfs=6.4)

    # ---- 右：decision_fsm ----
    rbox(ax, 52, 44, 24, 7, "段级决策结果",
         "seg_done · owner_valid(seg_own)\ncmd_id(seg_cmd[1:0])", fc=C_IO, ec=C_IO_E, sfs=6.4)
    rbox(ax, 52, 32, 24, 9, "decision_fsm 决策",
         "owner && cmd 有效 → 动作译码\n1→左(3) 2→右(4) 3→前(2) 0→停(0)", fc=C_MOD, sfs=6.6)
    rbox(ax, 30, 6, 56, 10, "顶层 seam（top_voice_robot.v）",
         "act_eff = (act==2) ? dir_act : act；dir_act：dir→左(3)/右(4)/前(2)\ndec_pulse（段末沿）→ vgoal → 运动链",
         fc=C_DEC, ec=C_DEC_E, tfs=8, sfs=6.4)

    elbow(ax, [(25, 47.5), (30, 47.5)], label="L/R 采样")
    elbow(ax, [(13, 42), (30, 46.5)], label="vad")
    elbow(ax, [(39, 44), (39, 40)], label="SL / SR")
    elbow(ax, [(39, 32), (39, 28)], label="比较")
    elbow(ax, [(64, 44), (64, 41)], label="段末结果")
    elbow(ax, [(64, 32), (64, 16)], label="o_cmd_valid/action")
    elbow(ax, [(39, 22), (39, 16)], label="dir[1:0]", color="#1F5AA5", lw=1.3)

    ax.text(2, 1.5,
            "dir_energy：VAD 段内幅度累加、交叉相乘（NUM/DEN=21/20，能量比 >1.05× 判偏侧）；"
            "decision_fsm 同时接收段级 owner 与 cmd，无语音→REJECT 不执行。",
            ha="left", fontsize=6.5, color="#666666")

    return save(fig, "fig17_decision_dir_circuit.png")


if __name__ == "__main__":
    fig11()
    fig12()
    fig13()
    fig14()
    fig15()
    fig16()
    fig17()
    print("全部生成完成")
