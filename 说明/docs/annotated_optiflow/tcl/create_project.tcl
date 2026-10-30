# =============================================================================
# create_project.tcl —— 逐行注释版（原文件 28 行）★ 一键重建"纯按键版"工程
# 与 create_project_cam.tcl 的区别只有三处：
#   1) 顶层是 top_button_game（没有摄像头，不需要 OV7725 驱动）
#   2) 不加 board_cam 目录（因为这个工程用不到摄像头）
#   3) 约束文件换成 top_button_game.xdc
# =============================================================================
# create_project.tcl — 重建 button_game 工程                                # 文件名与用途
# 用法： vivado -mode batch -source create_project.tcl                    # 用法说明
set root     [file dirname [info script]]                               # 变量 root = 脚本所在目录（可移植，不写死绝对路径）
set prj_name button_game                                                # 变量：工程名叫 button_game
set prj_dir  $root                                                      # 变量：工程目录 = 脚本所在目录
set rtl      [file join $root src rtl]                                  # 变量：源码目录

create_project -force $prj_name $prj_dir -part xc7a100tfgg484-2          # 建工程，器件 XC7A100T-FGG484-2

add_files -fileset sources_1 [glob -nocomplain [file join $rtl *.sv]]              # 加所有 .sv（含游戏、光流、两个顶层——光流模块虽然用不到也会被编进来，综合会当空模块剔除）
add_files -fileset sources_1 [glob -nocomplain [file join $rtl board_hdmi *.v]]    # 加 HDMI 配置驱动（按键版也要出 HDMI 画面）
set_property top top_button_game [current_fileset]                      # 指定顶层为 top_button_game（按键版）
add_files -fileset constrs_1 [file join $root constraints top_button_game.xdc]     # 加按键版的引脚约束

if {[get_ips -quiet hdmi_pll] eq ""} {                                  # 没有 hdmi_pll 就创建
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name hdmi_pll   # Clocking Wizard（MMCM）
    set_property -dict [list \                                          # 批量配置参数
        CONFIG.PRIM_IN_FREQ {50.000} \                                  #   输入 50MHz
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \                    #   输出 25MHz 像素时钟
        CONFIG.USE_LOCKED {true} \                                      #   用 locked 做复位释放
        CONFIG.USE_RESET {true} \                                       #   启用复位
        CONFIG.RESET_TYPE {ACTIVE_HIGH} \                               #   高有效复位
        CONFIG.PRIMITIVE {MMCM} \                                       #   MMCM 原语
    ] [get_ips hdmi_pll]                                                #   应用配置
    generate_target all [get_ips hdmi_pll]                              #   生成 IP 输出文件
}                                                                       # if 结束
update_compile_order -fileset sources_1                                 # 重排编译顺序
puts "==== PROJECT READY: [file join $prj_dir ${prj_name}.xpr] ===="     # 打印生成好的工程路径
