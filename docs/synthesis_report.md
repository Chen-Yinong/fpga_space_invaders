# 综合与实现报告

> 数据来源：**Vivado 2026.1 实际运行**（本仓库源码，`build/report/`）
> 器件：**xc7a100tfgg484-2**（野火升腾Pro）　顶层：**top_cam_game**
> 构建时间：2026-10-29　综合 WNS +9.300 ns → 布线后 WNS +3.428 ns（均满足）

## 1. 构建环境

| 项目 | 值 |
|---|---|
| EDA 版本 | Vivado 2026.1（官方推荐版本） |
| 器件型号 | `xc7a100tfgg484-2` |
| 顶层模块 | `top_cam_game`（光流手势版；按键版 `top_button_game` 可切换） |
| 设计语言 | SystemVerilog（13 个核心模块）+ Verilog-2001（7 个板级驱动） |
| 约束文件 | `board/top_cam_game.xdc`：53 个引脚 + `create_clock` 20/41.667 ns + 摄像头 CDC `set_false_path` |
| IP | `hdmi_pll`（Clocking Wizard / MMCM，50 MHz→25 MHz，脚本自动生成） |
| 综合/实现策略 | Vivado 默认策略 |
| 主机 | Intel Core Ultra 5 125H / 32 GB / Windows 11 |

## 2. 资源占用

### 2.1 综合后

来源：`build/report/10_synth_utilization.rpt`

| 资源 | 使用量 | 总量 | 占用率 |
|---|---|---|---|
| Slice LUTs | 16,374 | 63,400 | 25.83 % |
| Slice Registers (FF) | 6,793 | 126,800 | 5.36 % |
| Block RAM Tile | 48.5 | 135 | 35.93 % |
| DSP48E1 | 12 | 240 | 5.00 % |
| Bonded IOB | 53 | 285 | 18.60 % |
| BUFGCTRL | 5 | 32 | 15.63 % |

### 2.2 布线后（对应实际 bitstream）

来源：`build/report/20_impl_utilization.rpt`

| 资源 | 使用量 | 总量 | 占用率 |
|---|---|---|---|
| Slice LUTs | **16,265** | 63,400 | **25.65 %** |
| Slice Registers | **6,800** | 126,800 | **5.36 %** |
| Block RAM Tile | **48.5** | 135 | **35.93 %** |
| DSP48E1 | **12** | 240 | **5.00 %** |
| Bonded IOB | **53** | 285 | **18.60 %** |
| BUFGCTRL | 6 | 32 | 18.75 % |
| MMCME2_ADV | 1 | 6 | 16.67 % |

**分析**：**BRAM 是最高占用资源（35.9%）**，几乎全部来自灰度帧乒乓缓冲
（320×240×8bit × 2 帧 = 150 KB ≈ 48 个 RAMB36）；LUT 仅 25.65%，FF 仅 5.36%。
说明本设计的瓶颈在**片内存储容量**而非逻辑资源——这既是"为什么当前只做 640×480"
的直接依据，也说明若要提高分辨率，第一优先级是压缩帧缓冲（如降采样存灰度、
单帧+帧差）而不是担心逻辑不够。

综合→布线 LUT 仅减少 0.7%（16374→16265），无逻辑复制膨胀，说明代码可综合性良好。

## 3. 时序收敛

来源：`build/report/11_synth_timing_summary.rpt` / `21_impl_timing_summary.rpt`

| 阶段 | WNS (ns) | WHS (ns) | 端点总数 | 失败端点 |
|---|---|---|---|---|
| 综合后 | +9.300 | +0.022 | 14,168 | 0 |
| **布线后（最终）** | **+3.428** | **+0.090** | **14,175** | **0** |

- 结论：**All user specified timing constraints are met**；TNS/THS 均为 0
- 未约束路径：0；WPWS（脉宽）：+7.000 ns
- 三个时钟的用户约束：

| 时钟 | 周期 | 频率 | 处理方式 |
|---|---|---|---|
| `sys_clk` | 20.000 ns | 50 MHz | 正常分析 |
| `cam1_pclk` | 41.667 ns | 24 MHz | 正常分析 + `CLOCK_DEDICATED_ROUTE FALSE`（非专用时钟布线） |
| `clk_out1_hdmi_pll` | 40.000 ns | 25 MHz | MMCM 输出，与 `sys_clk` 同源 |
| `u_pll/inst/clk_in1`、`clkfbout_hdmi_pll` | 20.000 ns | 50 MHz | PLL 内部 |

- 布线延迟消耗 5.87 ns（9.300 → 3.428），主要来自跨 BRAM 与 300 路光流累加的长线；
  仍有 3.4 ns 余量
- **hold 余量 +0.090 ns 偏紧**：属"刚好满足"，若后续换更快像素时钟需提高布线努力度
  （`-directive Explore`）或加 `set_clock_uncertainty`

## 4. 功耗估计

来源：`build/report/24_impl_power.rpt`（vectorless 估算，无实测功耗仪）

| 项目 | 值 |
|---|---|
| 总片上功耗 | **0.282 W** |
| 动态功耗 | 0.182 W |
| 静态功耗 | 0.100 W |
| 结温估计 | 25.8 ℃ |

片上功耗不到 0.3 W；整机功耗主要在 HDMI 发送芯片、摄像头模组与显示器侧。

## 5. 优化过程与前后对比（评分项：性能与资源优化）

| 版本 | 改动 | 结果 | 判断依据 |
|---|---|---|---|
| V1.0 | 基线（光流 + 游戏 + HDMI） | 功能跑通 | — |
| V1.1 | 掩体 1152 bit 位图变量下标 → `get_bunk_x` case 固定坐标 | 实现阶段由**卡死**变通过 | 变量下标综合出巨型 MUX，Timing Optimization 不结束（技能包 S1） |
| V1.2 | XDC 行尾 `#` 注释清理 | bitstream 由**失败**变成功 | Tcl 不支持行尾注释，53 个引脚约束曾全部失效（技能包 S2） |
| V1.3 | 仿真 `TICK_DIV` 参数覆盖 | 回归从数十分钟 → 秒级 | 见 `sim/tb_game_core.sv`（技能包 S3） |
| V2.0（待做） | `lk_flow` 6 个 Σ 累加 FIFO 改同步复位 | 预计 FF↓、BRAM↑ | 综合日志 `Synth 8-4767`：RAM 带异步复位无法映射 BRAM |

## 6. 综合警告分析（真实日志）

| 警告 | 含义 | 结论 |
|---|---|---|
| `Synth 8-4767` × 7：`fifoA~E / fifoBX / fifoBY` 用寄存器实现 | RAM 带异步复位无法映射 BRAM | 已知优化点（V2.0），当前用 FF 实现，功能正确 |
| `Synth 8-7137`：fifo 寄存器同时有 Set 与 Reset | 仿真/综合可能不一致 | 与上条同源，一并整改 |
| `Synth 8-3917`：`led_stop/left/right` 恒 0 | LED 未使用（设计选择） | 正常，手势状态改由画中画显示 |
| `Synth 8-7129`：`flow_v`、`px[2:0]`、`py[2:0]` 无负载 | 未参与判据，被优化 | 正常 |
| `Project 1-498`：`CLOCK_DEDICATED_ROUTE` 综合阶段求值失败 | 该网表实现阶段才存在 | 正常，Vivado 自动移到 `.Xil/*_propImpl.xdc`，最终生效（布线后 DRC 通过） |

## 7. 复现方式

```bash
# 仓库根目录（Vivado 2026.1 在 PATH 或直接给绝对路径）
vivado -mode batch -source build/build.tcl

# 产物
build/report/00_metrics.txt          # 关键指标
build/report/10~25_*.rpt             # 11 份原始报告
build/cam_game/.../impl_1/*.bit      # bitstream（约 3.65 MB）
```

复现一致性要求：
1. 器件、Vivado 版本与上表一致；
2. `git clone` 后**不打开 GUI**，一条命令产出 bitstream；
3. 资源/时序与上表误差 ±2% 以内（综合策略不同会波动，需注明策略）。