# 测试数据与参考结果

## 1. 仿真黄金参考（本仓库实测）

| 项目 | 结果 |
|---|---|
| 工具 | ModelSim 10.5b（Intel FPGA Edition）；Vivado xsim 亦可 |
| 被测 | `src/game_core.sv` + `sim/tb_game_core.sv`（TICK_DIV=10 加速） |
| 编译 | 0 error / 4 warning |
| 断言 | **14/14 全 PASS** |
| 仿真时长 | 48.7 µs |
| 原始日志 | `sim/sim_log.txt` |

断言覆盖：

```
reset -> IDLE / lives=6 / 55 enemies / bunkers full / stage=1
start -> PLAY / win=0
auto-fire -> player bullets
left / right -> player moved
hit enemy -> score up
enemy fired bullets
ufo spawned by LFSR
enemy bullet hit -> lives down
```

## 2. 综合/实现实测（Vivado 2026.1 真实运行）

| 指标 | 值 |
|---|---|
| 器件 / 顶层 | `xc7a100tfgg484-2` / `top_cam_game` |
| LUT / FF | 16,265（25.65%）/ 6,800（5.36%） |
| BRAM / DSP | 48.5（35.93%）/ 12（5.00%） |
| WNS / WHS | +3.428 ns / +0.090 ns（14,175 端点，0 失败） |
| 功耗 | 0.282 W（动态 0.182 + 静态 0.100），结温 25.8 ℃ |
| bitstream | 3.65 MB |

完整报告：`build/report/`、`docs/synthesis_report.md`

## 3. 板级 vs 仿真比对

见 [`board/README.md`](../board/README.md) 的一致性记录表（板级实测后填写）。

## 4. 参考结果文件说明

| 文件 | 来源 | 用途 |
|---|---|---|
| `sim/sim_log.txt` | ModelSim 批处理 | 证明功能正确性（14 条断言） |
| `build/report/00_metrics.txt` | Vivado 批处理 | 关键指标汇总 |
| `build/report/*.rpt` | Vivado | 资源/时序/功耗/DRC 原始证据 |