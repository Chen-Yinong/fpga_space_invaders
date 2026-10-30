# =============================================================================
# create_project_cam.tcl —— 逐行注释版（原文件 29 行）★ 一键重建"手势控制版"工程
# 用法：在 Vivado 的 Tcl Console 里  source create_project_cam.tcl
#      或命令行  vivado -mode batch -source create_project_cam.tcl
# 它做的事：建一个 cam_game 工程 → 把 src/rtl 下所有源码加进来 →
#          指定顶层 top_cam_game → 加引脚约束 → 生成 25MHz 时钟 IP
# 注意：create_project.tcl 是"纯按键版"（顶层 top_button_game），这个是"摄像头手势版"。
# =============================================================================
# create_project_cam.tcl — 重建手势控制版工程（top_cam_game）              # 文件名与用途
# 用法： vivado -mode batch -source create_project_cam.tcl               # 用法说明
set root     [file dirname [info script]]                               # 变量 root = 本脚本所在目录（这样脚本放到哪都能跑，不写死路径）
set prj_name cam_game                                                   # 变量：工程名叫 cam_game
set prj_dir  $root                                                      # 变量：工程目录 = 脚本所在目录
set rtl      [file join $root src rtl]                                  # 变量：源码目录 = <root>/src/rtl

create_project -force $prj_name $prj_dir -part xc7a100tfgg484-2          # 建工程：-force 已存在就覆盖；器件型号 XC7A100T-FGG484-2（升腾Pro 开发板）

add_files -fileset sources_1 [glob -nocomplain [file join $rtl *.sv]]              # 加入 src/rtl 下所有 .sv（.sv 是 SystemVerilog：游戏、光流、顶层）
add_files -fileset sources_1 [glob -nocomplain [file join $rtl board_cam *.v]]     # 加入 board_cam 下的 .v（OV7725 摄像头驱动，厂商例程是 Verilog-2001）
add_files -fileset sources_1 [glob -nocomplain [file join $rtl board_hdmi *.v]]    # 加入 board_hdmi 下的 .v（HDMI 芯片 DDC 配置）
set_property top top_cam_game [current_fileset]                         # 指定顶层模块为 top_cam_game（光流手势版）
add_files -fileset constrs_1 [file join $root constraints top_cam_game.xdc]   # 加引脚/时序约束文件

if {[get_ips -quiet hdmi_pll] eq ""} {                                  # 如果工程里还没有 hdmi_pll 这个 IP，就创建它
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name hdmi_pll   # 创建 Clocking Wizard（MMCM 锁相环），实例名 hdmi_pll
    set_property -dict [list \                                          # 一次性配置这个 IP 的一堆参数
        CONFIG.PRIM_IN_FREQ {50.000} \                                  #   输入时钟 50MHz（板载晶振）
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \                    #   第 1 路输出要 25MHz（640×480@60 的像素时钟）
        CONFIG.USE_LOCKED {true} \                                      #   使能 locked 输出（等 MMCM 稳定后才能放复位）
        CONFIG.USE_RESET {true} \                                       #   使能复位输入
        CONFIG.RESET_TYPE {ACTIVE_HIGH} \                               #   复位是高有效
        CONFIG.PRIMITIVE {MMCM} \                                       #   用 MMCM 而不是老的 PLL 原语
    ] [get_ips hdmi_pll]                                                #   把这份配置应用到 hdmi_pll
    generate_target all [get_ips hdmi_pll]                              #   生成 IP 的 RTL/仿真/实现所需文件
}                                                                       # if 结束
update_compile_order -fileset sources_1                                 # 重新计算编译顺序（顶层在最前，被例化的模块在后）
puts "==== PROJECT READY: [file join $prj_dir ${prj_name}.xpr] ===="     # 打印工程文件路径，方便直接打开
