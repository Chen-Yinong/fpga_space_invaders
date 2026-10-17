# create_project.tcl — 重建 FPGA 工程（野火 升腾Pro / XC7A100T-FGG484-2）
# 用法：cd 到仓库根目录，然后
#   vivado -mode batch -source scripts/create_project.tcl
# 依据 docs/repo_conventions.md：工程必须由脚本重建，禁止手工 GUI 建工程

set root     [pwd]
set prj_name fpga_space_invaders
set prj_dir  [file join $root build $prj_name]

file mkdir [file dirname $prj_dir]
create_project -force $prj_name $prj_dir -part xc7a100tfgg484-2

# 源码
add_files -fileset sources_1 [glob -nocomplain [file join $root src rtl *.sv]]
add_files -fileset sources_1 [glob -nocomplain [file join $root src rtl board *.v]]
add_files -fileset sources_1 [glob -nocomplain [file join $root src rtl board cam *.v]]
set_property top top_cam_game [current_fileset]

# 约束
add_files -fileset constrs_1 [file join $root constraints top_cam_game.xdc]

# PLL IP：50MHz -> 25MHz 像素时钟
if {[get_ips -quiet hdmi_pll] eq ""} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name hdmi_pll
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ             {50.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
        CONFIG.USE_LOCKED               {true} \
        CONFIG.USE_RESET                {true} \
        CONFIG.RESET_TYPE               {ACTIVE_HIGH} \
        CONFIG.PRIMITIVE                {MMCM} \
    ] [get_ips hdmi_pll]
    generate_target all [get_ips hdmi_pll]
}

update_compile_order -fileset sources_1
puts "==== 工程已重建: $prj_dir ===="
puts "下一步：open_project \$prj_dir\\${prj_name}.xpr  然后 综合/实现/生成比特流"