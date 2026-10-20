# hand_bin_display

野火「升腾 Pro」XC7A100T-FGG484 独立小工程：OV7725 摄像头采集 -> 默认肤色阈值 -> 手部二值化掩膜 -> HDMI 显示。

画面含义：**手部像素显示白色（1），其余显示黑色（0）**，用于直观观察默认肤色分割效果，不包含任何标定或游戏逻辑。

## 硬件

- 野火升腾 Pro 开发板（XC7A100T-FGG484-2）
- OV7725 摄像头（DVP + SCCB）
- HDMI 显示器（板载 SiI9134 编码芯片）

## 目录

```
hand_bin_display/
├── create_project.tcl          # 一键重建 Vivado 工程
├── src/rtl/
│   ├── top_hand_bin.sv         # 顶层：采集 -> 肤色 -> 二值化 -> HDMI
│   ├── bin_frame_buf.sv        # 1bit 手部掩膜帧缓存（320x240 抽点，双时钟）
│   ├── rgb2ycrcb.sv            # RGB565 -> YCbCr
│   ├── vga_timing.sv           # 640x480@60 时序
│   ├── board_cam/              # OV7725 驱动（厂家例程）
│   └── board_hdmi/             # HDMI 芯片 I2C 配置（厂家例程）
├── constraints/top_hand_bin.xdc # 引脚与时钟约束
└── sim/tb_bin_frame_buf.sv      # 帧缓存读写仿真
```

## 重建工程

在本目录打开终端，运行：

```powershell
vivado -mode batch -source create_project.tcl
```

脚本会创建 `hand_bin_display.xpr`，自动添加源码、约束，并生成 HDMI 像素时钟 IP（`hdmi_pll`，50MHz -> 25MHz）。之后在 Vivado 中 Run Synthesis -> Run Implementation -> Generate Bitstream 即可。

## 仿真

帧缓存读写仿真（ModelSim）：

```powershell
vlib work
vlog -sv src/rtl/bin_frame_buf.sv sim/tb_bin_frame_buf.sv
vsim -c -do "run -all; quit -f" tb_bin_frame_buf
```

## 默认肤色阈值

在 `top_hand_bin.sv` 中固定为：

- Cb 95..125、Cr 145..180（2026-10-17 实测手部值收紧）
- 饱和度判据 `|Cb-128| + |Cr-128| >= 16`
- 暖色判据 `Cr - Cb >= 30`

如需现场调整，直接改 `top_hand_bin.sv` 中的 `always_comb skin` 表达式。
