# cam_dual/ —— 双模式合并版（光流 LK + 肤色质心，key0 任意时刻切换）

把队友的两套方案合成**一个比特流**：两套视觉前端同时运行，共用同一路摄像头数据、
同一套跨时钟域结构、同一个 `game_core` 与 `sprite_render`，只在
`cam1_pclk` 域的方向出口处二选一。

## 1. 目录内容

| 文件 | 说明 |
| --- | --- |
| `rtl/top_cam_dual.sv` | 新的顶层（唯一新增的 RTL，其余模块全部复用仓库现有文件） |
| `rtl/dual_extra.xdc` | 补充约束：key0 引脚（V17）+ `set_false_path sys_clk → cam1_pclk` |
| `top_cam_dual.bit` | 最终比特流（已在板上验证烧录） |
| `build/report/*.rpt` | 综合/实现/时序/DRC/方法论报告（与上方比特流同一次构建产出） |
| `build_dual.tcl` | 从零建工程 + 综合 + 实现 + 出比特流 + 报告 |
| `rerun_impl.tcl` | 只重跑实现（改约束后验证时序，不用重新综合） |
| `program_dual.tcl` | 烧录到板子 |
| `build/cam_dual2/` | 本地 Vivado 工程目录（git 忽略，可用脚本随时重建） |

## 2. 操作方式

```
key0 (V17)   任意时刻切换模式 —— 当前局作废、回到待机画面，key2 开新局
key2 (AA18)  开始 / 暂停 / 继续
key3 (AB18)  同模式重开

led_left  亮 = 光流模式
led_right 亮 = 肤色质心模式

右上角画中画 472,8 起 160×120：
  光流模式  = 矢量场标签（红=向左 / 绿=向右 / 深灰=静止）
  质心模式  = 二值化手势轮廓（白=肤色）+ 红色十字准星
```

切换时整局复位是**故意的**：两个前端的坐标/手感不同，带着残局切换
容易出诡异状态，干净重来最稳。

## 3. 构建与烧录

```bash
# 从零构建（约 8 分钟；DUAL_PROJ 环境变量可换工程目录名）
D:/fpga/2026.1/Vivado/bin/vivado.bat -mode batch -source is-it-possible-to-ai-it-perfect/cam_dual/build_dual.tcl
# 改了约束只想重跑实现（约 6 分钟，需已有工程目录）
DUAL_PROJ=cam_dual2 D:/fpga/2026.1/Vivado/bin/vivado.bat -mode batch -source is-it-possible-to-ai-it-perfect/cam_dual/rerun_impl.tcl
# 烧录（默认找 cam_dual2，DUAL_PROJ 可换）
DUAL_PROJ=cam_dual2 D:/fpga/2026.1/Vivado/bin/vivado.bat -mode batch -source is-it-possible-to-ai-it-perfect/cam_dual/program_dual.tcl
```

## 4. 合并怎么做的（三条边界）

1. **模块名冲突**：两套工程有 11 个同名文件（`top_cam_game.sv`、`game_core.sv`、
   `sprite_render.sv`、`vga_timing.sv`、`debounce.sv`、板级驱动……），不能整目录合并。
   做法：共享部分全部用仓库根 `src/`（交付版，BUNK_H=12），只额外引入质心版
   **独有的 4 个模块**：`rgb2ycrcb.sv`、`bin_frame_buf.sv`、`centroid_calc.sv`、`dir_judge.sv`
   （取自 `is-it-possible-to-ai-it-perfect/cam_game/src/rtl/`）。
2. **时序冻结**：不改 `vga_timing`（800×525 @ 25.175MHz ≈ 59.5Hz）、不改
   `TICK_DIV=833333`（游戏节拍 60Hz）、不改任何速度常量，merged 版本的游戏手感与
   已交付版本逐拍一致。
3. **共用跨域结构**：只在 `cam1_pclk` 域做一次二选一，之后仍然是
   “单根 2FF 同步器 + toggle 信箱快照”，跨时钟域路径数量没有增加。

## 5. 实测资源与时序（xc7a100tfgg484-2）

| 版本 | Slice LUT | 占比 | BRAM | DSP | WNS | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| 光流单版 | 16265 | 25.65% | 48.5 | 12 | +3.428 | 队友报告 |
| 质心单版 | 16774 | 26.46% | 3 | 0 | — | 队友报告 |
| **合并双模版** | **17744** | **27.99%** | **51.5** | **12** | **+0.988** | 0 违例端点 |

- 相比光流单版只多 **+1479 LUT（+2.3 个百分点）、+3 BRAM**，
  **远低于**“两版叠加”的悲观估计（33039 LUT / 52.1%）。
  原因是两版共享 `game_core`+`sprite_render`+信箱+2FF，新增的只是质心前端本身。
- WNS +0.988 为最终交付比特流（`key0` 任意时刻切换版）的实测值；
  质心前端判定路径较长，sys_clk 域裕量比单版（+3.428）低，改 `game_core` 前需重查时序。

## 6. 踩到的坑（值得写进报告）

**首次实现 WNS 为 -2.932ns，唯一违例端点是 `mode_flow → m1_reg`。**
模式寄存器在 `sys_clk` 域翻转，经 `m1/m2` 两级同步器进 `cam1_pclk` 域，但原
`board/top_cam_game.xdc` 只写了单向的

```tcl
set_false_path -from [get_clocks cam1_pclk] -to [get_clocks sys_clk]
```

反向缺失 → 工具把这条跨域路径按“单周期 0.004ns”分析，必然违例。
在 `rtl/dual_extra.xdc` 补上反向 `set_false_path` 后 WNS 回正。

> 这是 CDC 约束不对称的典型例子：**跨域例外要双向写**，只写单向会在引入反向信号时突然爆雷。

**第二版曾把模式切换门控在 IDLE 状态**，而 `game_core` 状态机一旦开局就
没有回 IDLE 的路径（`key3` 重开也是直接进 `S_PLAY`），导致开局后 key0 永久失效。
最终版去掉门控：`wire mode_chg = k0_rise;` —— 任意时刻可切，切换时整局复位回待机。

## 7. 已知限制

- **曝光设置不同**：仓库根 `src/board_cam/ov7725_cfg.v` 是光流版调的**固定曝光**
  （`{8'h08,0x02}` AECH、`{8'h10,0x00}` AEC），质心版的肤色阈值是在**自动曝光**下标定的。
  上板后如果质心模式偏色/漏检，改 `top_cam_dual.sv` 顶部的
  `CB_LO/CB_HI/CR_LO/CR_HI/WARM_MIN` 五个 localparam 即可，不用动判定结构。
- 两套前端同时运行，功耗略高于单版（估 +0.1~0.2W 量级），比赛演示无影响。
- **不要在 Vivado GUI 里对着 build/ 下的工程跑 `reset_run`**：曾因 GUI 与命令行
  构建抢同一个工程目录，`reset_run` 把综合网表和比特流全删了。要开 GUI 请开
  `build/cam_dual2/cam_dual2.xpr`，或者用 `DUAL_PROJ=xxx` 另起一个目录构建。
