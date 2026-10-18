# cam_game

野火「升腾 Pro」XC7A100T-FGG484 完全体工程：OV7725 摄像头手势控制 + 太空侵略者 + HDMI 画中画。

## 操作

- 手在摄像头前左右移动：炮台左右移动（质心位移，带迟滞去抖）
- key2（AA18）：开始 / 暂停 / 继续
- key3（AB18）：重开

## 画面

- 全屏黑白太空侵略者（55 外星人、4 掩体、自动连射、6 命、计分、敌弹、触底判负）
- 右上角 160x120 画中画：实时显示 OV7725 二值化手势画面（手白、背景黑）+ 红色十字准星（质心）

## 目录

```
cam_game/
├── create_project.tcl
├── src/rtl/
│   ├── top_cam_game.sv       # 整合顶层
│   ├── dir_judge.sv          # 手势方向判定（迟滞+去抖）
│   ├── game_core.sv          # 游戏本体
│   ├── sprite_render.sv      # 黑白渲染
│   ├── centroid_calc.sv      # 质心 + 帧间位移 dx
│   ├── bin_frame_buf.sv      # 1bit 手势帧缓存
│   ├── rgb2ycrcb.sv / debounce.sv / vga_timing.sv
│   ├── board_cam/            # OV7725 驱动
│   └── board_hdmi/           # HDMI 芯片配置
├── constraints/top_cam_game.xdc
└── sim/
```

## 重建工程

```powershell
vivado -mode batch -source create_project.tcl
```
