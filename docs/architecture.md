# 系统架构与数据流

> 作品：摄像头光流控制的《太空侵略者》——挥手操控炮台、光流矢量场画中画显示（自主选题赛道 · 初级组）
> 硬件：野火升腾Pro XC7A100T-FGG484-2 · OV7725 摄像头 · HDMI 显示器
> 工具链：Vivado 2026.1 · SystemVerilog + 厂商驱动 Verilog
> **全部图表见 [diagrams/space_invaders_architecture.drawio](diagrams/space_invaders_architecture.drawio)**（draw.io 打开，5 个页面；可导出 PNG 插入报告）

| drawio 页 | 内容 | 建议导出文件名 |
|---|---|---|
| 1-系统架构图 | 三时钟域横带全景 | arch_overview.png |
| 2-数据流图 | 光流链 + 游戏/显示链（蛇形） | dataflow.png |
| 3-时钟域与CDC | 3 域 2 处异步跨域 | clock_domain.png |
| 4-游戏主状态机 | 4 态 Moore FSM | fsm_main.png |
| 5-手势判决FSM | flow_fsm 三级决策 | fsm_gesture.png |

## 1. 架构分层（真实实现：top_cam_game）

| 层 | 模块 | 时钟域 | 职责 |
|---|---|---|---|
| 采集 | `ov7725_top`（含 `ov7725_cfg/ov7725_data/i2c_ctrl`） | cam1_pclk | SCCB 配置 OV7725，DVP 8bit 拼成 RGB565 |
| 感知 | `rgb2gray` → `gray_framebuf` → `flow_linebuf` → `lk_flow` | cam1_pclk | 灰度化 → 乒乓双缓冲 → 行缓冲梯度 → 16×16 块 LK 光流（Q16 定点，`div_pipe` 70 拍除法） |
| 决策 | `flow_fsm` + `flow_tag_ram` | cam1_pclk | 300 块投票 → 帧方向判定 → 漏桶积分 → 手势命令；标签双口 RAM 供画中画 |
| 控制 | `debounce` ×2 + `game_core` | sys_clk 50MHz | 按键消抖；游戏全部状态与规则（60Hz tick） |
| 显示 | `vga_timing` + `sprite_render` + 画中画叠加 + `hdmi_i2c` | clk_25m 25MHz | 640×480@60 时序；组合坐标比较渲染；ADV7511 配置 |

**为什么 game_core 只输出"数据"不输出"像素"**：把游戏规则与显示实现解耦，
game_core 是可独立仿真的纯逻辑模块（12 条断言的 testbench 验证），换板卡/换分辨率时
只需替换显示层，核心不动。手势版（`top_cam_game`）与按键版（`top_button_game`）共用同一核心。

## 2. 数据流（见 drawio 第 2 页）

1. **像素流**：OV7725 输出 8bit×2 拍拼成 RGB565（cam1_pclk ≈24MHz）
2. **灰度**：`(R×77+G×150+B×29)>>8`，光流只关心亮度
3. **双缓冲**：`gray_framebuf` 整帧乒乓，同时提供上一帧/当前帧
4. **梯度**：`flow_linebuf` 延迟一行，每像素得 Ix、Iy、It
5. **块解算**：`lk_flow` 2×2 抽点、16×16 分块，累加 ΣA~E，`div_pipe` 恢复余数法 70 拍除法，解 2×2 方程得 (u,v) Q16
6. **手势**：`flow_fsm` 三级决策（投票→帧判定→漏桶）输出 gest_left/right
7. **跨域**：2FF 同步器进 50MHz 域（镜像反转：画面左=游戏右）
8. **游戏**：game_core 60Hz tick 推进，对象寄存器 + 组合碰撞判决
9. **快照**：toggle 信箱每 4096 拍（81.9µs）整包复制到 25MHz 显示域
10. **渲染**：`sprite_render` 组合坐标比较出颜色 + 光流矢量画中画 → HDMI

## 3. 状态机设计（答辩问题 1 的完整答案）

**全设计共 2 个主要状态机 + 3 个辅助时序控制器 + 若干板级配置状态机：**

### 3.1 主控制 FSM（game_core 的 `state`，见 drawio 第 4 页）

| 状态 | 编码 | 含义 | 是否推进游戏 |
|---|---|---|---|
| `S_IDLE` | `2'd0` | 上电待机，显示标题 | 否 |
| `S_PLAY` | `2'd1` | 游戏进行中 | 是 |
| `S_PAUSE` | `2'd2` | 暂停，画面冻结 | 否 |
| `S_OVER` | `2'd3` | 结束（`win` 区分胜负） | 否 |

迁移表（完整版见 drawio 图内标注）：

| 当前状态 | 条件 | 次态 | 同步动作 |
|---|---|---|---|
| 任意 | `rst_n==0` | `S_IDLE` | 异步复位 |
| 任意 | `btn_restart↑` | `S_PLAY` | **全量复位**（分数/生命/关卡/掩体/UFO/定时器） |
| `S_IDLE`/`S_OVER` | `btn_start↑` | `S_PLAY` | 全量复位 |
| `S_PLAY` | `btn_start↑` | `S_PAUSE` | 冻结推进 |
| `S_PAUSE` | `btn_start↑` | `S_PLAY` | 恢复推进 |
| `S_PLAY` | `lives==0` 或 敌阵触底 | `S_OVER` | `win=0` |
| `S_PLAY` | 敌全灭 且 `stage==3` | `S_OVER` | `win=1` |
| `S_PLAY` | 敌全灭 且 `stage<3` | `S_PLAY` | `stage_clear` 序列 120 拍 → 关卡+1 |

设计方式：**Moore 型**，单 `always_ff` + 优先级 if 链（复位 > restart > start > 游戏逻辑），
迁移只在 60Hz tick 使能沿采样（`if (tick)`），天然无毛刺；状态直接门控游戏是否推进。

### 3.2 手势判决 FSM（flow_fsm，见 drawio 第 5 页）

三级顺序决策（摄像头域），不是经典编码状态机而是流水化判决器：

1. **逐块投票**：每块能量 ≥E_MIN 且 |u|≥0.125px 才可信，u 符号投左/右票（帧内累计，vsync 清零）
2. **帧方向判定**：左票 ≥2 且比右票多 ≥2 → 本帧判左（对称判右）；票不足/矛盾 → 无效帧
3. **漏桶积分**：bucket ∈ [-8,+8]，帧左-1/帧右+1，静止漏电回 0；**|bucket|≥3 才输出手势**

设计动机：LK 单帧误判率高，阈值只能设很低（0.125px/帧，靠方向一致性）；
投票聚合 300 块弱证据，漏桶滤除偶发抖动且天然保留静止态。

### 3.3 辅助时序控制器（常被追问，一并准备）

| 名称 | 组成 | 行为 |
|---|---|---|
| `stage_clear` 序列 | 标志 + 8bit 计数 | 敌全灭后冻结 120 拍做通关字幕（闪烁），之后关卡+1 重建战场 |
| UFO 生命周期 | `ufo_active_r` + 16bit 随机倒数 | LFSR 决定出现时机 → 右移巡航 → 飞出消失，分值 50/100/150/300 |
| 受击无敌 | `inv_cnt` 8bit 倒数 | 被击中后 60 拍不判伤，`inv_cnt[4]` 控制闪烁 |
| 板级配置状态机 | `ov7725_cfg`（SCCB 写表）、`i2c_ctrl`（16 态）、`hdmi_cfg` | 上电按序配置摄像头/HDMI 芯片寄存器 |

## 4. 时钟域与复位（答辩问题 2 的完整答案）

**3 个时钟、2 处异步跨域、1 处同源跨域（见 drawio 第 3 页）：**

| 时钟域 | 频率 | 来源 | 承载模块 |
|---|---|---|---|
| `cam1_pclk` 摄像头域 | ≈24 MHz | OV7725 独立晶振 | 采集、灰度、LK 光流、手势判决 |
| `sys_clk` 系统域 | 50 MHz | 板载晶振（W19） | 按键消抖、game_core（60Hz tick） |
| `clk_25m` 显示域 | 25 MHz | **MMCM 由 50MHz 同源分频** | vga_timing、sprite_render、HDMI |

**协调规则（这是评委最想听的）：**

1. **摄像头域 → 系统域（①）**：手势是单 bit 信号，过**两级触发器同步器**（并做镜像反转：
   摄像头镜像输出，画面左=现实右）；XDC 声明 `set_false_path -from cam1_pclk -to sys_clk`
2. **摄像头域 → 显示域（②）**：光流标签走 `flow_tag_ram` **双口 RAM**（pclk 写 / 25MHz 读），
   天然隔离两个域；XDC 同样声明 false_path
3. **系统域 → 显示域（③）**：两个时钟**同源**（MMCM 分频、相位对齐），STA 直接按同步路径
   分析，无需同步器；用 **toggle 信箱**（每 4096 拍翻转，81.9µs）触发整包快照复制，
   保证游戏状态一次搬完、画面不撕裂
4. **节拍策略**：游戏内部用**时钟使能**（tick，50MHz÷833333≈60Hz）而非分频时钟，
   game_core 内部单一时钟域、零 CDC
5. **复位**：`rst_n = sys_rst_n & locked`（MMCM 未锁定不放复位），异步复位、锁定后释放

**经验教训（写进报告的优化对比）**：早期版本掩体用 1152bit 向量变量下标访问，综合出
巨型 MUX 导致 Timing Optimization 阶段卡死，改 `get_bunk_x` case 返回固定坐标后解决
——这是"综合失败→定位→修复"的完整案例。

## 5. 验证与实测

| 项目 | 方法 | 结果 |
|---|---|---|
| 功能仿真 | `sim/tb_game_core.sv`（TICK_DIV 参数覆盖加速 + 12 条断言） | 全部断言通过 |
| 上板验证 | OV7725 + HDMI：挥手控制、画中画矢量场、完整游戏流程 | 已跑通（照片/视频存 `board/`） |
| 资源/时序 | `build/build.tcl` 自动导出 | 见 `docs/synthesis_report.md` |

## 6. 复现步骤

```bash
# 一键重建工程 + 综合 + 实现 + bit + 报告
vivado -mode batch -source build/build.tcl

# 行为仿真（Vivado GUI）
#   Flow Navigator → Run Simulation → Run Behavioral Simulation → Tcl: run -all
```