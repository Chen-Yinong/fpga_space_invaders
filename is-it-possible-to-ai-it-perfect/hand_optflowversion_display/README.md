# hand_leftorright（光流版）

野火「升腾 Pro」XC7A100T-FGG484 独立小工程：OV7725 摄像头采集 -> Lucas-Kanade 半稠密光流场 -> 左右挥手判定 -> HDMI 矢量场显示。

这是“方案二：稠密/半稠密硬件光流场估计”的落地实现，彻底抛弃肤色二值化，直接根据像素运动的时空梯度解出运动矢量。背景、肤色、光线、桌面材质都不影响判定——静止的物体运动矢量恒为 0。

## 数据通路

摄像头 RGB565 -> 灰度 -> 双缓冲帧缓存（当前帧/上一帧）-> 3x3 时空窗口求 Ix/Iy/It -> 像素梯度门限 -> 16x16 块内累加结构张量 A/B/C/D/E -> 克莱姆法则解 (u,v) -> 左右方向投票 -> 漏桶积分器 -> LED。

求解公式（与方案二一致）：

```text
u = (B*E - C*D) / (A*C - B^2)
v = (B*D - A*E) / (A*C - B^2)
```

其中 A=ΣIx²、B=ΣIxIy、C=ΣIy²、D=ΣIxIt、E=ΣIyIt，在 16x16 块（处理域）内求和。处理域为 320x240（640x480 每 2x2 抽一点），共 20x15 = 300 个块，即半稠密矢量场。

## 目录

```text
hand_leftorright_for-new-try/
├── create_project_flow.tcl       # 一键重建光流版工程（top = top_flow）
├── create_project.tcl            # 旧肤色版重建脚本（保留）
├── src/rtl/
│   ├── top_flow.sv               # 顶层：采集 -> 光流 -> 手势 FSM -> HDMI
│   ├── lk_flow.sv                # LK 光流核心（窗口/累加/克莱姆求解）
│   ├── gray_framebuf.sv          # 双缓冲灰度帧缓存（2 x 320x240 x 8bit）
│   ├── flow_linebuf.sv           # 处理域行缓冲
│   ├── div_pipe.sv               # 流水线恢复除法器（定点 Q16）
│   ├── flow_fsm.sv               # 矢量汇总 + 施密特迟滞 + 显示标签
│   ├── flow_tag_ram.sv           # 块运动标签双口 RAM
│   ├── rgb2gray.sv               # RGB565 -> 8bit 灰度
│   ├── vga_timing.sv             # 640x480@60 时序
│   ├── board_cam/                # OV7725 驱动（厂家例程）
│   ├── board_hdmi/               # HDMI 芯片 I2C 配置（厂家例程）
│   └── （旧肤色版 top_hand_bin.sv / centroid_calc.sv / bin_frame_buf.sv / rgb2ycrcb.sv 保留，未被引用）
├── constraints/top_hand_bin.xdc  # 引脚与时钟约束（端口与旧版一致）
└── sim/
    ├── tb_lk_flow.sv             # 光流核心自检（平移纹理块）
    └── tb_flow_fsm.sv            # 手势状态机自检（施密特迟滞）
```

## 重建工程

在本目录打开终端，运行：

```powershell
vivado -mode batch -source create_project_flow.tcl
```

脚本会创建 `hand_leftorright_flow.xpr`，top 设为 `top_flow`，并生成 HDMI 像素时钟 IP（`hdmi_pll`，50MHz -> 25MHz）。之后在 Vivado 中 Run Synthesis -> Run Implementation -> Generate Bitstream。

## 仿真

光流核心（iverilog）：

```powershell
iverilog -g2012 -o sim_tb.out src/rtl/rgb2gray.sv src/rtl/gray_framebuf.sv src/rtl/flow_linebuf.sv src/rtl/div_pipe.sv src/rtl/lk_flow.sv sim/tb_lk_flow.sv
vvp sim_tb.out
```

手势状态机（iverilog）：

```powershell
iverilog -g2012 -o tb_fsm.out src/rtl/flow_tag_ram.sv src/rtl/flow_fsm.sv sim/tb_flow_fsm.sv
vvp tb_fsm.out
```

## 显示含义

HDMI 输出半稠密矢量场：明显左移的块显示红色，明显右移的块显示绿色，其余为黑。三个 LED：`led_stop`（停止/慢速）、`led_left`（明显向左）、`led_right`（明显向右）。

## 摄像头固定曝光

`board_cam/ov7725_cfg.v` 已把 COM8（0x13）从 `0xff` 改为 `0xf8`，关闭自动曝光（AEC）、自动白平衡（AWB）和自动增益（AGC），避免这些自动调节让整帧亮度缓慢漂移、被光流误判成持续朝一个方向的运动。同时在配置末尾加入固定曝光值 `{AECH, AEC} = 0x0200`（约 16ms）。

如果上板后画面偏暗或偏亮，调整 `cfg_data_reg[69]`（AECH 0x08，高字节）和 `cfg_data_reg[70]`（AEC 0x10，低字节）的值即可，曝光值越大画面越亮。

## 关键参数

判定阈值集中在 `src/rtl/flow_fsm.sv` 的 parameter 里（定点 Q16，1.0 = 65536，单位是处理域像素/帧）：

- `U_MIN`：单块计入投票的最小 |u|（默认 0.125；LK 会低估帧间位移，设小、靠方向一致性投票）
- `E_MIN`：块梯度能量下限，过滤无纹理/低可信块（默认 8000）
- `CNT_MIN`：一帧内单方向至少几票才可能判定（默认 2）
- `MAJORITY`：优势方向至少比对方多出的票数（默认 2）
- `TH_BUCKET`：漏桶点亮阈值，连续几帧同向才点亮 LED（默认 3）
- `BUCKET_MAX`：漏桶饱和值（默认 8）

光流结构参数在 `src/rtl/lk_flow.sv`：

- `BLOCK`：块边长（默认 16，越大越抗噪但矢量越稀疏）
- `DET_MIN`：det 绝对值下限，低于此判为不可信（默认 1000000，防孔径退化除法溢出）
- `GRAD_MIN`：像素梯度门限，|Ix|+|Iy| 低于此不参与累加（默认 24，过滤平坦区噪声）
- `QF`：定点小数位（默认 16）
