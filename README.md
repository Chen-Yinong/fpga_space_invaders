# FPGA 光流手势控制的《太空侵略者》

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道（AMD）· 自主选题赛道 · 初级组

对着摄像头**挥一挥手**就能左右移动激光炮台——不是按键、不是手机 App，而是 FPGA 内部
用纯硬件解算的 **Lucas-Kanade 光流**：300 个图像块并行算运动矢量，投票+漏桶判决出方向，
驱动完整的经典街机游戏，输出到 HDMI 显示器。右上角画中画实时显示光流矢量场，
让算法"看得见"。

| | |
|---|---|
| 器件 | 野火升腾Pro **XC7A100T-FGG484-2** |
| 输入 | OV7725 摄像头（DVP 8bit / SCCB 配置）+ 2 个按键 |
| 输出 | HDMI 640×480@60（24bit RGB）+ 画中画矢量场 |
| 工具链 | **Vivado 2026.1** |
| 规模 | 20 个 RTL 文件 / 2879 行 |
| 实测 | LUT 16,265（25.7%）、BRAM 48.5、DSP 12、WNS **+3.43 ns**、功耗 0.28 W |

## 作品特性

1. **手势控制**：手只区分三种状态——静止、明显向左、明显向右；挥手即炮台移动，停手即停
2. **纯硬件光流**：`lk_flow` 在 24 MHz 摄像头域内对 20×15=300 块并行解算 (u,v)（Q16 定点），
   自研 70 拍流水除法器
3. **鲁棒判决**：`flow_fsm` 三级决策（逐块投票 → 帧方向判定 → 漏桶积分 ±8），
   单帧误判被滤除，静止自动回中立
4. **可解释的调试**：右上角画中画实时渲染矢量场（红=左 / 绿=右 / 灰=静止）
5. **完整街机规则**：55 只外星人（11×5）、4 座可逐位破坏的掩体、6 发并行子弹、
   随机神秘飞碟（50/100/150/300 分）、3 关递进、胜负结算
6. **经典街机分色**：顶行浅蓝、中间白色、底部黄色，掩体绿色，飞碟红色
7. **工程化架构**：3 个时钟域（24/50/25 MHz），2 处异步 CDC（2FF 同步器、双口 RAM）
   + 1 处同源信箱快照，全程无亚稳态风险

## 目录结构（官方推荐结构）

```
├── README.md                 本文件：项目简介 + 复现步骤
├── src/                      设计源码
│   ├── *.sv                  13 个 SystemVerilog 模块（光流/游戏/渲染/顶层）
│   ├── board_cam/*.v         OV7725 驱动（SCCB 配置 + DVP 采集）
│   └── board_hdmi/*.v        HDMI 发送芯片 I2C 配置
├── sim/                      仿真
│   ├── tb_game_core.sv       测试平台（TICK_DIV 参数加速 + 14 条断言）
│   └── sim_log.txt           实测仿真日志（14/14 PASS）
├── build/
│   ├── build.tcl             一键重建（含 hdmi_pll IP 自动生成）
│   └── report/               综合/实现/时序/功耗/DRC 报告
├── board/                    上板材料
│   ├── top_cam_game.xdc      引脚 + 时序 + CDC 约束（53 个引脚）
│   ├── top_button_game.xdc   按键版约束（无摄像头对照版本）
│   └── top_cam_game.bit      已验证 bitstream
├── data/                     测试数据与参考结果
├── skill/                    技能包（8 条，全部来自真实踩坑）
├── report/                   设计报告
├── docs/                     架构/硬件/综合报告 + drawio 图源文件
└── 说明/                     开发过程文档（协作日志、接口规范、脚本、工作区说明）
```

## 快速开始

### 一条命令构建（评委复现用）

```bash
vivado -mode batch -source build/build.tcl
# 产出 build/report/*.rpt 与 build/cam_game/.../impl_1/top_cam_game.bit
```

### 仿真

Vivado GUI → Add Sources → `sim/tb_game_core.sv` → Run Behavioral Simulation →
Tcl 控制台 `run -all`
预期：14 条断言全部 `[PASS]`，以 `==== TB_GAME ALL PASS ====` 结束。

### 上板

1. Hardware Manager 烧写 `board/top_cam_game.bit`
2. 摄像头朝向操作者，光照充足、背景有纹理（光流需要纹理）
3. 操作：**挥手左右**移动炮台；**key2** 开始/暂停/继续；**key3** 重开
4. 验收：挥手时画中画对应区域变红/绿，停手变灰

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 系统架构、数据流、**状态机设计**、**时钟域与 CDC** |
| [docs/hardware_setup.md](docs/hardware_setup.md) | 传感器/执行器/接线/供电（引脚全真实值） |
| [docs/synthesis_report.md](docs/synthesis_report.md) | 综合与实现报告（实测数据 + 优化对比） |
| [docs/diagrams/space_invaders_architecture.drawio](docs/diagrams/space_invaders_architecture.drawio) | 5 张图（架构/数据流/时钟域/主FSM/手势FSM），draw.io 可编辑 |
| [report/report.md](report/report.md) | 设计报告正文 |
| [skill/README.md](skill/README.md) | 技能包 8 条 |
| [说明/docs/ai_collaboration.md](说明/docs/ai_collaboration.md) | 大模型协作日志 |

## 两个可交付版本

| 顶层 | 输入 | 说明 |
|---|---|---|
| `top_cam_game` | 摄像头光流手势 + key2/key3 | **主提交版本** |
| `top_button_game` | 4 按键 | 无摄像头环境的对照/演示版 |

## 许可

MIT，见 [LICENSE](LICENSE)。