# B4 Feature Engine — Interface & Fixed-Point Specification（v1，待确认）

> 状态：**审计完成，本阶段只出规格，未写 RTL**。确认后再实现 feature_engine。
> 范围：把已各自 PASS 的 B3 积木（pre_emph/front_wind/fft_core/mel_bank/log2_lut/dct2_mfcc）统一成
> “一帧 PCM → 13 维 MFCC”的 `feature_engine.v`。**不改/不删已 PASS 的 B3 模块逻辑**。

## 1. 代码审计结论（基于仓库实际文件，非臆测）

### 1.1 各 B3 模块真实接口与默认参数
| 模块 | 默认参数 | 输入 | 输出 | 备注 |
|---|---|---|---|---|
| pre_emph | AW=24, Q=14, A_FIX=15892 | in_valid, x[23:0] signed | out_valid, y[23:0] signed(饱和) | 流式，一拍流水 |
| front_wind | AW=24, **N=64** | sample_ok, sample[23:0] | out_valid/out_first, out_data[23:0] | 单缓冲、hop=N、Q15 Hann；`$readmemh("data/hann_64.mem")` 硬编码 64 |
| fft_core | AW=24, **N=16** | in_valid, in_re[23:0]（位倒序载入） | out_valid, re/im[31:0] | radix-2 DIT、Q15 旋转因子、逐级 >>1≈DFT/N；ROM 文件名硬编码 16 |
| mel_bank | **NB=9, M=6**, CFQ=12 | in_valid, in_pow[31:0] | out_valid, out_mel[63:0] | Σ pow·coef >>12；系数 `mel_coef.mem` |
| log2_lut | XW=48, FW=8, BW=6 | in_valid, in_x[47:0] | out_l[15:0] | log2 LUT 近似，x=0→0 |
| logmel_chain | NB=9,M=6,CFQ=12,XW=48 | 同 mel_bank | out_logmel[15:0] | mel→log 串链 |
| dct2_mfcc | **M=6, K=4**, DQ=12 | in_valid, in_x[15:0]×M | out_valid, out_c[31:0]×K | DCT-II，基 `dct_basis.mem` |
| vtmpl(C2-lite) | **DIM=4**, TH=500 | in_valid, in_v[15:0]×DIM | out_dist[31:0], out_match | L1 距离+阈值 |

**结论：默认参数相互不一致（见文档头）→ B3 不能按默认直接串接。** 同时满足“13 维 MFCC”目标也必须改 DCT 尺寸。

### 1.2 已 PASS 但尺寸固定的小测试
每个积木都只有**单套固定尺寸向量**（hann_64、tw_16、mel 9×6、dct 6→4、log 6 值）。改为统一尺寸 = 需为这些积木**重生成向量并重跑 PASS**（不是重写算法）。

## 2. 统一参数方案（Proposal，待确认）
在“尽量不改已验证算法、只改尺寸与 ROM”原则下，推荐：

| 项目 | 数值 | 说明 |
|---|---|---|
| Sample Rate | 48 kHz 名义（实测≈48076） | ES8388 MCLK 12.307692MHz/256 |
| PCM Width | 24 bit signed | 与 audio_pcm_bridge / codec 一致 |
| Frame Length / FFT_N / hop | **64 / 64 / 64** | 非重叠 v1；hop=N 简化，后续可加 overlap |
| Frame period | 64/48000 ≈ **1.33 ms** | |
| Power bins | 33（DC..Nyquist） | N/2+1 |
| Mel Filters M | **20** | 0..fs/2 三角窗 |
| MFCC Dimension | **13** | K=13 ≤ M |
| Channel | L / R / mono 可选 | 默认 L；不丢 R（方向用 el/er 单独保留） |
| VAD | enable/bypass（test_mode） | 不改 VAD 本体 |

**必须随之重生成/重验证的积木测试**：hann_64(已 64，保留)、tw_64、mel(33,20)、dct(M=20,K=13)、log 不变、以及新增 Power 级。

> 备选（更小、几乎零重验）：N=16→NB=9→M=6→**K≤4**。**不满足 13 维 MFCC**，仅建议作为“最小可跑”引擎参考，不作为本目标。

## 3. 定点格式（每级，可综合整数实现）
| 级 | 输入格式 | 输出格式 | 舍入/饱和 |
|---|---|---|---|
| PCM | int24 signed（整数，无小数） | 同左 | — |
| Pre-emph y | int24 | int24 signed 饱和 | 饱和到 int24 |
| Window | int24 × Q15(win∈[0,1]) | int24 signed 饱和 | (p+HALF)>>>15 |
| FFT | int24（位倒序） | int32 re/im ≈ DFT/N | 每级和差 >>>1（floor）；tw Q15 |
| Power(新) | int32 re/im | **uint 低位宽（>>PS 定标）** | (r²+i²)>>>PS；PS 定标使 mel 不溢出 |
| Mel | uint × Q12 系数 | 宽累加 → >>12 | floor |
| Log | XW=48 | int16 log2（FW=8, BW=6 LUT） | x=0→0 |
| DCT | int16 × Q12 基 | int32 → **定标后 int16**（喂 vtmpl） | >>>12 floor |
| MFCC 输出 | — | 13×int16（帧内逐维） | 由 DCT 定标决定 |

## 4. B4 RTL 架构
```
IDLE→LOAD_FRAME(64×24 入 RAM/reg)→PRE_EMPH+WINDOW(存 64 窗值)
→FFT(N=64, 位倒序载入, 蝶形)→POWER(33 bins)→MEL(20)→LOG(20)
→DCT(K=13)→OUTPUT(13×feature)→IDLE
```
- 复用积木顺序连接；新增小级仅 `power`（组合/寄存器 MAC）。
- 每级 valid 握手：上一级 out_valid 打下一级 in_valid（与 logmel_chain/ctl_chain 同风格）。
- `feature_index[3:0]`、`feature_valid`、`frame_done`、`busy` 与既有各模块脉冲一致。
- RAM/ROM：窗/旋转因子/Mel 基/DCT 基/Log LUT → BRAM/分布式 RAM 初始化 .mem；不新增时钟域、不引入浮点。

## 5. 验证分层（不是只比最终）
Python `py/gen_feature_engine.py` 用同一套固定算法逐级输出：
`pre_emph/window/fft/power/mel/log/mfcc` 参考；TB 逐级打印，任何级失配可定位。
- Test1 全零、Test2 1kHz 单频、Test3 定种子伪随机帧。
- RTL vs Python：每级小容差；MFCC 用明确 abs/rel（按定点实测标定，不用超大容差“造 PASS”）。
- 保留全部 B3 单模块 TB。

## 6. 实时性/资源（估算；最终以综合报告为准）
- 计算周期粗估：载 64 + FFT 192 + power 33 + mel 660 + log20 + dct260 ≈ 1.2k 周期 ≈ **24µs**。
- 帧周期 **1.33ms** ⇒ 24µs ≪ 1.33ms，**可实时**（非重叠）；若后续 overlap=hop 减半仍有余量。
- 资源预计：乘/累加器少量复用、多块 .mem ROM；LUT/FF/BRAM 数值下板综合后统计（EG4S20：19600 LUT / ~1Mb BRAM）。

## 7. 与 C2/vtmpl 接口
`feature_engine` 每帧输出 13 维（int16，经 DCT 定标）→ `vtmpl #(.DIM(13))` 逐维喂入。vtmpl 阈值按真实特征标定（当前 500 为占位）。

## 8. 前置依赖与待你拍板点
1. 采用 **N=64/M=20/K=13/hop=64** 方案？（则需按 §2 重生成并重跑 mel/fft/dct 尺寸级向量）
2. Power 定标 PS、DCT→16bit 定标具体取多大 → 由 Python 定标实验定，定标参数化暴露成 parameter。
3. MFCC 输入声道：v1 默认 **L**，mono 用 (L+R)/2 需多一个加法级——是否要做由资源余量定。

> 确认以上后，才进入“写 feature_engine → gen_feature_engine.py → tb_feature_engine → 分层仿真 → 资源分析 → git commit”。
