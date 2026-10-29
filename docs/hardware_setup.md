# 传感器、执行器、接线与供电说明

> 实际硬件：野火升腾Pro XC7A100T-FGG484-2 开发板 + OV7725 摄像头模组 + HDMI 显示器
> 引脚号全部来自工程约束 `board/top_cam_game.xdc`（板卡原理图已核对），无估计值。

## 1. 硬件清单 (BOM)

| 类别 | 名称 | 规格/型号 | 数量 | 备注 |
|---|---|---|---|---|
| 主控 | 野火升腾Pro 开发板 | XC7A100T-FGG484-2 | 1 | 板载 50MHz 晶振、复位按键、QSPI Flash |
| 传感器 | OV7725 摄像头模组 | DVP 接口，RGB565 输出 | 1 | 含 SCCB（类 I2C）配置线，3.3V 供电 |
| 执行器 | HDMI 显示器 | 支持 640×480@60 | 1 | 经板上 HDMI 发送芯片（ADV7511 类）输出 |
| 输入 | 板载按键 | key2 / key3 | 2 | 低有效；key2=开始/暂停，key3=重开 |
| 指示 | 板载 LED | 3 个（M21/L21/K21） | 3 | 本工程恒灭（手势状态改由画中画显示） |
| 线材 | 排线摄像头连接线、HDMI 线、USB 供电线 | — | 各 1 | |

## 2. 传感器（输入）接口表

### 2.1 OV7725 摄像头（主传感器，手势输入）

| 信号 | FPGA 引脚 | 方向 | 电平 | 说明 |
|---|---|---|---|---|
| `cam1_pclk` | AA21 | 输入 | LVCMOS33 | 像素时钟 ≈24MHz（独立晶振，异步时钟域） |
| `cam1_href` | T21 | 输入 | LVCMOS33 | 行有效（高=该行像素有效） |
| `cam1_vsync` | T18 | 输入 | LVCMOS33 | 场同步（帧边界） |
| `cam1_data[0]` | N14 | 输入 | LVCMOS33 | 8bit 并行数据 bit0 |
| `cam1_data[1]` | N13 | 输入 | LVCMOS33 | bit1 |
| `cam1_data[2]` | R19 | 输入 | LVCMOS33 | bit2 |
| `cam1_data[3]` | P19 | 输入 | LVCMOS33 | bit3 |
| `cam1_data[4]` | U22 | 输入 | LVCMOS33 | bit4 |
| `cam1_data[5]` | AA20 | 输入 | LVCMOS33 | bit5 |
| `cam1_data[6]` | R18 | 输入 | LVCMOS33 | bit6 |
| `cam1_data[7]` | U21 | 输入 | LVCMOS33 | bit7（RGB565 一个像素占 2 个 pclk） |
| `cam_rst_n` | P16 | 输出 | LVCMOS33 | 摄像头复位（本工程恒高=不复位） |
| `cam_pwdn` | R17 | 输出 | LVCMOS33 | 掉电控制（恒低=正常工作） |
| `sccb1_scl` | R14 | 输出 | LVCMOS33 | SCCB 配置时钟 |
| `sccb1_sda` | P14 | 双向 | LVCMOS33 | SCCB 配置数据（三态控制） |

### 2.2 按键与系统信号

| 信号 | FPGA 引脚 | 方向 | 电平 | 说明 |
|---|---|---|---|---|
| `sys_clk` | W19 | 输入 | LVCMOS33 | 板载 50MHz 晶振（`create_clock -period 20.000`） |
| `sys_rst_n` | N15 | 输入 | LVCMOS33 | 板载复位按键，低有效 |
| `key2` | AA18 | 输入 | LVCMOS33 | 开始/暂停/继续（低有效，经 5ms 消抖） |
| `key3` | AB18 | 输入 | LVCMOS33 | 重开（低有效，上升沿优先级最高） |

## 3. 执行器（输出）接口表

### 3.1 HDMI 输出（主执行器）

| 信号 | FPGA 引脚 | 方向 | 电平 | 说明 |
|---|---|---|---|---|
| `hdmi_out_clk` | K18 | 输出 | LVCMOS33 | 像素时钟 25MHz |
| `hdmi_out_rst_n` | J16 | 输出 | LVCMOS33 | HDMI 芯片复位 |
| `hdmi_out_hsync` | K17 | 输出 | LVCMOS33 | 行同步 |
| `hdmi_out_vsync` | J17 | 输出 | LVCMOS33 | 场同步 |
| `hdmi_out_de` | K19 | 输出 | LVCMOS33 | 数据有效（高=RGB 有效） |
| `hdmi_out_rgb[23:16]` R 通道 | H13/G13/G15/G16/G17/G18/J14/H14 | 输出 | LVCMOS33 | 红色 8bit（高位在前） |
| `hdmi_out_rgb[15:8]` G 通道 | J15/H15/H17/H18/J19/H19/H20/G20 | 输出 | LVCMOS33 | 绿色 8bit |
| `hdmi_out_rgb[7:0]` B 通道 | J20/J21/J22/H22/K13/K14/L16/K16 | 输出 | LVCMOS33 | 蓝色 8bit |
| `ddc_scl` | E19 | 输出 | LVCMOS33 | DDC(I2C) 时钟，配置 HDMI 发送芯片 |
| `ddc_sda` | D19 | 双向 | LVCMOS33 | DDC(I2C) 数据 |

### 3.2 LED（本工程未点亮，保留引脚）

| 信号 | 引脚 | 状态 |
|---|---|---|
| `led_stop` / `led_left` / `led_right` | M21 / L21 / K21 | 恒灭（手势状态改由画中画矢量场显示，避免 LED 刺眼） |

## 4. 供电说明

| 设备 | 供电方式 | 说明 |
|---|---|---|
| 升腾Pro 开发板 | USB 5V 或 DC 适配器 | 板载稳压产生 3.3V/1.0V；**不要同时接两种** |
| OV7725 模组 | 开发板排座 3.3V | 模组自带稳压，电流 <100mA |
| HDMI 显示器 | 独立 220V | 与板共地（HDMI 线自带地） |

**上电顺序**：开发板上电 → 摄像头完成 SCCB 寄存器配置（`ov7725_cfg` 状态机自动执行）→
HDMI 芯片 DDC 初始化 → MMCM locked 后 `rst_n` 释放 → 游戏进入 `S_IDLE` 待机。
**操作说明**：向左挥手=炮台左移，向右挥手=右移（摄像头镜像输出已做左右对调），停手=停；
key2 开始/暂停，key3 重开。

## 5. 时钟与跨域约束（XDC 关键行）

```tcl
create_clock -period 20.000 -name sys_clk   [get_ports sys_clk]     # 50MHz
create_clock -period 41.667 -name cam1_pclk [get_ports cam1_pclk]   # 24MHz
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam1_pclk_IBUF]  # pclk 走普通布线
set_false_path -from [get_clocks cam1_pclk] -to [get_clocks clk_out1_hdmi_pll]  # CDC 例外
set_false_path -from [get_clocks cam1_pclk] -to [get_clocks sys_clk]
set_property CFGBVS VCCO [current_design]   # 3.3V bank 配置
set_property CONFIG_MODE SPIx4 [current_design]  # QSPI 下载
```

## 6. 接线检查清单（上板前逐项确认）

- [ ] 摄像头排线方向正确（pclk/href/vsync/data 顺序按模组丝印）
- [ ] 摄像头镜头朝向玩家挥手方向，视野内避免强光直射（光流依赖纹理）
- [ ] HDMI 线插紧，显示器设置为 640×480@60（多数显示器自动识别）
- [ ] 复位按键可正常按下（N15）
- [ ] 现象异常时：看画中画矢量场——红/绿块不动说明光流失败（检查光照/镜头）

## 7. 常见故障与排查

| 现象 | 可能原因 | 排查 |
|---|---|---|
| 画面全黑 | HDMI 芯片未配置成功 / MMCM 未锁定 | 复位一次；确认 `ddc_scl/sda` 接线 |
| 画中画全灰 | 光流无结果：光照不足/镜头遮挡/摄像头未出图 | 检查摄像头排线与 SCCB 配置完成标志 |
| 手势方向反了 | 镜像反转逻辑与摄像头安装方向不匹配 | 交换 `gl_s2/gr_s2` 接线或调整摄像头朝向 |
| 手势乱闪 | 漏桶阈值与场景不匹配 | 调 `TH_BUCKET`/`E_MIN` 参数；改善光照 |
| 按键无响应 | 未消抖或按住时间过短 | 按住 ≥5ms；确认 key2/key3 引脚 |
| 上板与仿真不一致 | 仿真覆盖了 TICK_DIV | 上板用默认 833333（60Hz），逻辑一致仅速度不同 |