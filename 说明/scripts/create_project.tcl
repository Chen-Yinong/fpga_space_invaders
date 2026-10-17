# create_project.tcl — 重建可移植工程（相对路径）
# 用法：在仓库根目录执行： vivado -mode batch -source 说明/scripts/create_project.tcl
set root     [pwd]
set prj_name fpga_space_invaders
set prj_dir  [file join $root fpga_space_invaders]
set rtl      [file join $root fpga_space_invaders src rtl]

create_project -force $prj_name $prj_dir -part xc7a100tfgg484-2

add_files -fileset sources_1 [glob -nocomplain [file join $rtl *.sv]]
add_files -fileset sources_1 [glob -nocomplain [file join $rtl board *.v]]
add_files -fileset sources_1 [glob -nocomplain [file join $rtl board cam *.v]]
set_property top top_cam_game [current_fileset]
add_files -fileset constrs_1 [file join $root fpga_space_invaders constraints top_cam_game.xdc]

if {[get_ips -quiet hdmi_pll] eq ""} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name hdmi_pll
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ              {50.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
        CONFIG.USE_LOCKED                {true} \
        CONFIG.USE_RESET                 {true} \
        CONFIG.RESET_TYPE                {ACTIVE_HIGH} \
        CONFIG.PRIMITIVE                 {MMCM} \
    ] [get_ips hdmi_pll]
    generate_target all [get_ips hdmi_pll]
}
update_compile_order -fileset sources_1
puts "==== PROJECT READY: [file join $prj_dir ${prj_name}.xpr] ===="