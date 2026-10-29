# =============================================================================
# top_button_game.xdc —— 逐行注释版（原文件 87 行）★ 按键版引脚约束
# 与 top_cam_game.xdc 相比，少了摄像头那 20 个引脚、少了 pclk 时钟和两条 CDC 例外，
# 多了 key0/key1（摄像头版只用了 key2/key3）。
# =============================================================================
# top_button_game.xdc — 升腾Pro XC7A100T-FGG484-2：按键版太空侵略者 + HDMI       # 文件用途
set_property CFGBVS VCCO [current_design]                                # 配置 bank 电压跟随 VCCO
set_property CONFIG_VOLTAGE 3.3 [current_design]                         # 配置 IO 电压 3.3V
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]            # bit 流走 Quad SPI（4 线）
set_property CONFIG_MODE SPIx4 [current_design]                          # 配置模式 SPIx4
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]             # 配置时钟 50MHz

# -------- 系统时钟 / 复位 --------                                          # —— 时钟与复位 ——
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]                     # 系统时钟电平 3.3V
set_property PACKAGE_PIN W19 [get_ports sys_clk]                         # 系统时钟接 W19（50MHz 晶振）
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]            # 声明 20ns 周期（50MHz）
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]                   # 复位电平
set_property PACKAGE_PIN N15 [get_ports sys_rst_n]                       # 复位接 N15（低有效）

# -------- 按键（低有效）--------                                            # —— 四个按键 ——
set_property IOSTANDARD LVCMOS33 [get_ports key0]                        # key0 电平
set_property PACKAGE_PIN V17 [get_ports key0]                            # key0 接 V17（本工程保留给扩展用，顶层未使用）
set_property IOSTANDARD LVCMOS33 [get_ports key1]                        # key1 电平
set_property PACKAGE_PIN W17 [get_ports key1]                            # key1 接 W17（同上，未使用）
set_property IOSTANDARD LVCMOS33 [get_ports key2]                        # key2 电平
set_property PACKAGE_PIN AA18 [get_ports key2]                           # key2 接 AA18（开始/暂停）
set_property IOSTANDARD LVCMOS33 [get_ports key3]                        # key3 电平
set_property PACKAGE_PIN AB18 [get_ports key3]                           # key3 接 AB18（重开）

# -------- HDMI 输出 --------                                               # —— HDMI 输出 ——
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_clk]                # 像素时钟电平
set_property PACKAGE_PIN K18 [get_ports hdmi_out_clk]                    # 25MHz 像素时钟接 K18
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_rst_n]              # HDMI 芯片复位电平
set_property PACKAGE_PIN J16 [get_ports hdmi_out_rst_n]                  # 复位接 J16
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_hsync]              # 行同步电平
set_property PACKAGE_PIN K17 [get_ports hdmi_out_hsync]                  # 行同步接 K17
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_vsync]              # 场同步电平
set_property PACKAGE_PIN J17 [get_ports hdmi_out_vsync]                  # 场同步接 J17
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_de]                 # 数据有效电平
set_property PACKAGE_PIN K19 [get_ports hdmi_out_de]                     # DE 接 K19
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[23]}]          # 红色最高位电平
set_property PACKAGE_PIN H13 [get_ports {hdmi_out_rgb[23]}]              # R7 接 H13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[22]}]          # 红 bit6 电平
set_property PACKAGE_PIN G13 [get_ports {hdmi_out_rgb[22]}]              # R6 接 G13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[21]}]          # 红 bit5 电平
set_property PACKAGE_PIN G15 [get_ports {hdmi_out_rgb[21]}]              # R5 接 G15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[20]}]          # 红 bit4 电平
set_property PACKAGE_PIN G16 [get_ports {hdmi_out_rgb[20]}]              # R4 接 G16
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[19]}]          # 红 bit3 电平
set_property PACKAGE_PIN G17 [get_ports {hdmi_out_rgb[19]}]              # R3 接 G17
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[18]}]          # 红 bit2 电平
set_property PACKAGE_PIN G18 [get_ports {hdmi_out_rgb[18]}]              # R2 接 G18
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[17]}]          # 红 bit1 电平
set_property PACKAGE_PIN J14 [get_ports {hdmi_out_rgb[17]}]              # R1 接 J14
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[16]}]          # 红 bit0 电平
set_property PACKAGE_PIN H14 [get_ports {hdmi_out_rgb[16]}]              # R0 接 H14
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[15]}]          # 绿色最高位电平
set_property PACKAGE_PIN J15 [get_ports {hdmi_out_rgb[15]}]              # G7 接 J15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[14]}]          # 绿 bit6 电平
set_property PACKAGE_PIN H15 [get_ports {hdmi_out_rgb[14]}]              # G6 接 H15
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[13]}]          # 绿 bit5 电平
set_property PACKAGE_PIN H17 [get_ports {hdmi_out_rgb[13]}]              # G5 接 H17
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[12]}]          # 绿 bit4 电平
set_property PACKAGE_PIN H18 [get_ports {hdmi_out_rgb[12]}]              # G4 接 H18
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[11]}]          # 绿 bit3 电平
set_property PACKAGE_PIN J19 [get_ports {hdmi_out_rgb[11]}]              # G3 接 J19
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[10]}]          # 绿 bit2 电平
set_property PACKAGE_PIN H19 [get_ports {hdmi_out_rgb[10]}]              # G2 接 H19
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[9]}]           # 绿 bit1 电平
set_property PACKAGE_PIN H20 [get_ports {hdmi_out_rgb[9]}]               # G1 接 H20
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[8]}]           # 绿 bit0 电平
set_property PACKAGE_PIN G20 [get_ports {hdmi_out_rgb[8]}]               # G0 接 G20
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[7]}]           # 蓝色最高位电平
set_property PACKAGE_PIN J20 [get_ports {hdmi_out_rgb[7]}]               # B7 接 J20
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[6]}]           # 蓝 bit6 电平
set_property PACKAGE_PIN J21 [get_ports {hdmi_out_rgb[6]}]               # B6 接 J21
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[5]}]           # 蓝 bit5 电平
set_property PACKAGE_PIN J22 [get_ports {hdmi_out_rgb[5]}]               # B5 接 J22
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[4]}]           # 蓝 bit4 电平
set_property PACKAGE_PIN H22 [get_ports {hdmi_out_rgb[4]}]               # B4 接 H22
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[3]}]           # 蓝 bit3 电平
set_property PACKAGE_PIN K13 [get_ports {hdmi_out_rgb[3]}]               # B3 接 K13
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[2]}]           # 蓝 bit2 电平
set_property PACKAGE_PIN K14 [get_ports {hdmi_out_rgb[2]}]               # B2 接 K14
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[1]}]           # 蓝 bit1 电平
set_property PACKAGE_PIN L16 [get_ports {hdmi_out_rgb[1]}]               # B1 接 L16
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[0]}]           # 蓝 bit0 电平
set_property PACKAGE_PIN K16 [get_ports {hdmi_out_rgb[0]}]               # B0 接 K16
set_property IOSTANDARD LVCMOS33 [get_ports ddc_scl]                     # DDC 时钟电平
set_property PACKAGE_PIN E19 [get_ports ddc_scl]                         # DDC SCL 接 E19
set_property IOSTANDARD LVCMOS33 [get_ports ddc_sda]                     # DDC 数据电平
set_property PACKAGE_PIN D19 [get_ports ddc_sda]                         # DDC SDA 接 D19
