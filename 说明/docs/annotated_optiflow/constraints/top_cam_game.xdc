# =============================================================================
# top_cam_game.xdc —— 逐行注释版（原文件 131 行）★ 引脚约束 + 时序约束
# XDC 不是 Verilog，它告诉 Vivado 三件事：
#   1) 每个信号接在芯片的哪个物理引脚上（PACKAGE_PIN）
#   2) 这些引脚用什么电平标准（IOSTANDARD LVCMOS33 = 3.3V 单端）
#   3) 时钟频率多少、哪些路径不用做时序分析（create_clock / set_false_path）
# 写错 PACKAGE_PIN 的最典型现象：综合能过、下板没反应，或者画面花屏。
# =============================================================================
# top_cam_game.xdc — 升腾Pro XC7A100T-FGG484-2：手势（光流）控制版太空侵略者   # 文件用途（.xdc 里 # 是注释）
set_property CFGBVS VCCO [current_design]                                # 配置组的 bank 电压跟随 VCCO（3.3V bank 必须这么写，否则报错）
set_property CONFIG_VOLTAGE 3.3 [current_design]                         # 声明配置 IO 电压 3.3V（与硬件一致，供 Vivado 检查电平匹配）
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]            # bit 流用 Quad SPI（x4）下载，速度比单线快 4 倍
set_property CONFIG_MODE SPIx4 [current_design]                          # 配置模式 SPIx4（板载 QSPI Flash 就是 4 线）
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]             # 配置时钟 50MHz（下载速度，太高可能不稳定）

# -------- 系统时钟 / 复位 --------                                          # —— 时钟与复位 ——
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]                     # sys_clk 用 3.3V 单端电平
set_property PACKAGE_PIN W19 [get_ports sys_clk]                         # sys_clk 接 FPGA 的 W19 脚（板载 50MHz 有源晶振）
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]            # 声明周期 20ns（=50MHz）的时钟，Vivado 靠它算时序余量
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]                   # 复位脚电平 3.3V
set_property PACKAGE_PIN N15 [get_ports sys_rst_n]                       # 复位接 N15（板载复位按键，低有效）

# -------- OV7725 摄像头（DVP + SCCB）--------                              # —— 摄像头接口 ——
set_property IOSTANDARD LVCMOS33 [get_ports cam1_pclk]                   # 摄像头像素时钟电平
set_property PACKAGE_PIN AA21 [get_ports cam1_pclk]                      # pclk 接 AA21（摄像头输出的像素时钟，约 24~25MHz）
set_property IOSTANDARD LVCMOS33 [get_ports cam1_href]                   # 行有效信号电平
set_property PACKAGE_PIN T21 [get_ports cam1_href]                       # href 接 T21（这一行有像素数据时拉高）
set_property IOSTANDARD LVCMOS33 [get_ports cam1_vsync]                  # 场同步电平
set_property PACKAGE_PIN T18 [get_ports cam1_vsync]                      # vsync 接 T18（一帧结束/开始时跳变）
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[0]}]              # 数据线第 0 位电平
set_property PACKAGE_PIN N14 [get_ports {cam1_data[0]}]                  # 数据线 bit0 接 N14
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[1]}]              # 数据线第 1 位电平
set_property PACKAGE_PIN N13 [get_ports {cam1_data[1]}]                  # 数据线 bit1 接 N13
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[2]}]              # 数据线第 2 位电平
set_property PACKAGE_PIN R19 [get_ports {cam1_data[2]}]                  # 数据线 bit2 接 R19
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[3]}]              # 数据线第 3 位电平
set_property PACKAGE_PIN P19 [get_ports {cam1_data[3]}]                  # 数据线 bit3 接 P19
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[4]}]              # 数据线第 4 位电平
set_property PACKAGE_PIN U22 [get_ports {cam1_data[4]}]                  # 数据线 bit4 接 U22
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[5]}]              # 数据线第 5 位电平
set_property PACKAGE_PIN AA20 [get_ports {cam1_data[5]}]                 # 数据线 bit5 接 AA20
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[6]}]              # 数据线第 6 位电平
set_property PACKAGE_PIN R18 [get_ports {cam1_data[6]}]                  # 数据线 bit6 接 R18
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[7]}]              # 数据线第 7 位电平
set_property PACKAGE_PIN U21 [get_ports {cam1_data[7]}]                  # 数据线 bit7（最高位）接 U21；8 位并行，RGB565 分两个 pclk 传完
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n]                   # 摄像头复位电平
set_property PACKAGE_PIN P16 [get_ports cam_rst_n]                       # 复位接 P16（低有效，平时拉高）
set_property IOSTANDARD LVCMOS33 [get_ports cam_pwdn]                    # 摄像头掉电控制电平
set_property PACKAGE_PIN R17 [get_ports cam_pwdn]                        # 接 R17（拉低=工作，拉高=掉电省电）
set_property IOSTANDARD LVCMOS33 [get_ports sccb1_scl]                   # SCCB 时钟电平（SCCB 是 OV 公司的简化 I2C）
set_property PACKAGE_PIN R14 [get_ports sccb1_scl]                       # SCL 接 R14
set_property IOSTANDARD LVCMOS33 [get_ports sccb1_sda]                   # SCCB 数据电平
set_property PACKAGE_PIN P14 [get_ports sccb1_sda]                       # SDA 接 P14（双向线，模块内部要三态控制）

# -------- 按键（低有效，开始/重开）--------                                # —— 按键 ——
set_property IOSTANDARD LVCMOS33 [get_ports key2]                        # key2 电平
set_property PACKAGE_PIN AA18 [get_ports key2]                           # key2 接 AA18（开始/暂停）
set_property IOSTANDARD LVCMOS33 [get_ports key3]                        # key3 电平
set_property PACKAGE_PIN AB18 [get_ports key3]                           # key3 接 AB18（重开）

# -------- HDMI 输出 --------                                               # —— HDMI 输出 ——
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_clk]                # 像素时钟输出电平
set_property PACKAGE_PIN K18 [get_ports hdmi_out_clk]                    # 像素时钟 25MHz 接 K18（送给 HDMI 芯片）
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_rst_n]              # HDMI 芯片复位电平
set_property PACKAGE_PIN J16 [get_ports hdmi_out_rst_n]                  # 复位接 J16
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_hsync]              # 行同步电平
set_property PACKAGE_PIN K17 [get_ports hdmi_out_hsync]                  # 行同步接 K17
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_vsync]              # 场同步电平
set_property PACKAGE_PIN J17 [get_ports hdmi_out_vsync]                  # 场同步接 J17
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_de]                 # 数据有效（Data Enable）电平
set_property PACKAGE_PIN K19 [get_ports hdmi_out_de]                     # DE 接 K19（DE=1 时 RGB 才有效）
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[23]}]          # RGB 第 23 位（红色最高位）电平
set_property PACKAGE_PIN H13 [get_ports {hdmi_out_rgb[23]}]              # R7 接 H13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[22]}]          # RGB 第 22 位电平
set_property PACKAGE_PIN G13 [get_ports {hdmi_out_rgb[22]}]              # R6 接 G13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[21]}]          # RGB 第 21 位电平
set_property PACKAGE_PIN G15 [get_ports {hdmi_out_rgb[21]}]              # R5 接 G15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[20]}]          # RGB 第 20 位电平
set_property PACKAGE_PIN G16 [get_ports {hdmi_out_rgb[20]}]              # R4 接 G16
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[19]}]          # RGB 第 19 位电平
set_property PACKAGE_PIN G17 [get_ports {hdmi_out_rgb[19]}]              # R3 接 G17
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[18]}]          # RGB 第 18 位电平
set_property PACKAGE_PIN G18 [get_ports {hdmi_out_rgb[18]}]              # R2 接 G18
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[17]}]          # RGB 第 17 位电平
set_property PACKAGE_PIN J14 [get_ports {hdmi_out_rgb[17]}]              # R1 接 J14
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[16]}]          # RGB 第 16 位（最低位红）电平
set_property PACKAGE_PIN H14 [get_ports {hdmi_out_rgb[16]}]              # R0 接 H14；至此 8 位红 = bit23..16
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[15]}]          # RGB 第 15 位（绿色最高位）电平
set_property PACKAGE_PIN J15 [get_ports {hdmi_out_rgb[15]}]              # G7 接 J15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[14]}]          # RGB 第 14 位电平
set_property PACKAGE_PIN H15 [get_ports {hdmi_out_rgb[14]}]              # G6 接 H15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[13]}]          # RGB 第 13 位电平
set_property PACKAGE_PIN H17 [get_ports {hdmi_out_rgb[13]}]              # G5 接 H17
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[12]}]          # RGB 第 12 位电平
set_property PACKAGE_PIN H18 [get_ports {hdmi_out_rgb[12]}]              # G4 接 H18
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[11]}]          # RGB 第 11 位电平
set_property PACKAGE_PIN J19 [get_ports {hdmi_out_rgb[11]}]              # G3 接 J19
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[10]}]          # RGB 第 10 位电平
set_property PACKAGE_PIN H19 [get_ports {hdmi_out_rgb[10]}]              # G2 接 H19
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[9]}]           # RGB 第 9 位电平
set_property PACKAGE_PIN H20 [get_ports {hdmi_out_rgb[9]}]               # G1 接 H20
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[8]}]           # RGB 第 8 位（最低位绿）电平
set_property PACKAGE_PIN G20 [get_ports {hdmi_out_rgb[8]}]               # G0 接 G20；至此 8 位绿 = bit15..8
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[7]}]           # RGB 第 7 位（蓝色最高位）电平
set_property PACKAGE_PIN J20 [get_ports {hdmi_out_rgb[7]}]               # B7 接 J20
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[6]}]           # RGB 第 6 位电平
set_property PACKAGE_PIN J21 [get_ports {hdmi_out_rgb[6]}]               # B6 接 J21
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[5]}]           # RGB 第 5 位电平
set_property PACKAGE_PIN J22 [get_ports {hdmi_out_rgb[5]}]               # B5 接 J22
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[4]}]           # RGB 第 4 位电平
set_property PACKAGE_PIN H22 [get_ports {hdmi_out_rgb[4]}]               # B4 接 H22
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[3]}]           # RGB 第 3 位电平
set_property PACKAGE_PIN K13 [get_ports {hdmi_out_rgb[3]}]               # B3 接 K13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[2]}]           # RGB 第 2 位电平
set_property PACKAGE_PIN K14 [get_ports {hdmi_out_rgb[2]}]               # B2 接 K14
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[1]}]           # RGB 第 1 位电平
set_property PACKAGE_PIN L16 [get_ports {hdmi_out_rgb[1]}]               # B1 接 L16
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[0]}]           # RGB 第 0 位（蓝色最低位）电平
set_property PACKAGE_PIN K16 [get_ports {hdmi_out_rgb[0]}]               # B0 接 K16；至此 8 位蓝 = bit7..0
set_property IOSTANDARD LVCMOS33 [get_ports ddc_scl]                     # DDC 时钟电平（DDC 是用 I2C 读显示器能力的通道）
set_property PACKAGE_PIN E19 [get_ports ddc_scl]                         # DDC SCL 接 E19
set_property IOSTANDARD LVCMOS33 [get_ports ddc_sda]                     # DDC 数据电平
set_property PACKAGE_PIN D19 [get_ports ddc_sda]                         # DDC SDA 接 D19（用来配置 HDMI 发送芯片的工作模式）

# -------- 方向指示 LED（高电平点亮）--------                               # —— LED ——
set_property IOSTANDARD LVCMOS33 [get_ports led_stop]                    # LED 电平
set_property PACKAGE_PIN M21 [get_ports led_stop]                        # 停止指示 LED 接 M21
set_property IOSTANDARD LVCMOS33 [get_ports led_left]                    # LED 电平
set_property PACKAGE_PIN L21 [get_ports led_left]                        # 向左指示 LED 接 L21
set_property IOSTANDARD LVCMOS33 [get_ports led_right]                   # LED 电平
set_property PACKAGE_PIN K21 [get_ports led_right]                       # 向右指示 LED 接 K21

# -------- 摄像头 pclk：允许 IO->BUFG 非专用布线（24MHz 可接受）--------     # —— pclk 特殊约束 ——
create_clock -period 41.667 -name cam1_pclk [get_ports cam1_pclk]        # 声明 pclk 周期 41.667ns（=24MHz）为时钟
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam1_pclk_IBUF]      # 允许 pclk 走普通布线进 BUFG（不用专用时钟脚也行，24MHz 速率低没问题）

# -------- 跨时钟域 ----                                                    # —— CDC 例外 ——
set_false_path -from [get_clocks cam1_pclk] -to [get_clocks clk_out1_hdmi_pll]   # 摄像头域 → 显示域 用握手/双缓冲同步，不做时序分析
set_false_path -from [get_clocks cam1_pclk] -to [get_clocks sys_clk]     # 摄像头域 → 系统域 同理（省得 Vivado 报跨时钟域违例）
