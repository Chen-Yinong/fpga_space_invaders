# =============================================================================
#  cam_dual/build_dual.tcl —— 双模式合并版（光流 + 肤色质心，key0 切换）
#  器件: xc7a100tfgg484-2   顶层: top_cam_dual
#
#  用法（仓库根目录）:
#      D:/fpga/2026.1/Vivado/bin/vivado.bat -mode batch -source is-it-possible-to-ai-it-perfect/cam_dual/build_dual.tcl
#      （环境变量 DUAL_PROJ=xxx 可换工程目录名，默认 cam_dual）
#
#  产出:
#      cam_dual/build/report/*.rpt        综合/实现/时序/DRC 报告
#      cam_dual/build/$PROJ/.../impl_1/top_cam_dual.bit
# =============================================================================

set PART  xc7a100tfgg484-2
set TOP   top_cam_dual
set PROJ  cam_dual
if {[info exists ::env(DUAL_PROJ)]} { set PROJ $::env(DUAL_PROJ) }

set SCRIPT   [file normalize [info script]]
set MERGEDIR [file normalize [file join [file dirname $SCRIPT]]]
set ROOT     [file normalize [file join $MERGEDIR .. ..]]
set SRCDIR   [file join $ROOT src]
set CAMDIR   [file join $ROOT src board_cam]
set HDMIDIR  [file join $ROOT src board_hdmi]
set CENTDIR  [file join $ROOT is-it-possible-to-ai-it-perfect cam_game src rtl]
set CONSDIR  [file join $ROOT board]
set BUILDDIR [file join $MERGEDIR build]
set PROJDIR  [file join $BUILDDIR $PROJ]
set RPT      [file join $BUILDDIR report]
file mkdir $RPT

puts "== ROOT: $ROOT"
puts "== PART: $PART   TOP: $TOP"

# ---- 1. 建工程 ----
create_project -force $PROJ $PROJDIR -part $PART

set srcs [glob -nocomplain -directory $SRCDIR  -types f *.sv]
lappend srcs {*}[glob -nocomplain -directory $CAMDIR  -types f *.v]
lappend srcs {*}[glob -nocomplain -directory $HDMIDIR -types f *.v]
# 质心版独有的 4 个模块（其余模块名与 src/ 重复，不能整目录加入）
foreach f {rgb2ycrcb.sv bin_frame_buf.sv centroid_calc.sv dir_judge.sv} {
    lappend srcs [file join $CENTDIR $f]
}
# cam_dual 自己的 RTL（top_cam_dual.sv + dir_judge_acc.sv 等，整目录加入）
lappend srcs {*}[glob -nocomplain -directory [file join $MERGEDIR rtl] -types f *.sv]
if {[llength $srcs] == 0} { error "没有找到源文件" }
add_files -fileset sources_1 $srcs
set_property top $TOP [current_fileset]

foreach x [list [file join $CONSDIR top_cam_game.xdc] [file join $MERGEDIR rtl dual_extra.xdc]] {
    if {![file exists $x]} { error "找不到约束文件: $x" }
    add_files -fileset constrs_1 $x
}

# ---- 2. 时钟 IP: hdmi_pll (MMCM 50MHz -> 25MHz) ----
if {[get_ips -quiet hdmi_pll] eq ""} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name hdmi_pll
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {50.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
        CONFIG.USE_LOCKED {true} \
        CONFIG.USE_RESET {true} \
        CONFIG.RESET_TYPE {ACTIVE_HIGH} \
        CONFIG.PRIMITIVE {MMCM} \
    ] [get_ips hdmi_pll]
    generate_target all [get_ips hdmi_pll]
}

# ---- 3. 综合 ----
puts "== launch synth_1"
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
puts "== synth_1 status: $st"
if {[string first "synth_design Complete" $st] < 0} {
    set f [file join $PROJDIR ${PROJ}.runs synth_1 runme.log]
    if {[file exists $f]} { puts [exec tail -n 40 $f] }
    error "synth_1 未完成: $st"
}

# ---- 4. 实现 + bitstream ----
puts "== launch impl_1"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
puts "== impl_1 status: $st"
if {[string first "write_bitstream Complete" $st] < 0} {
    set f [file join $PROJDIR ${PROJ}.runs impl_1 runme.log]
    if {[file exists $f]} { puts [exec tail -n 40 $f] }
    error "impl_1 未完成: $st"
}

open_run impl_1
puts "== WNS: [get_property STATS.WNS [current_run]]   WHS: [get_property STATS.WHS [current_run]]"

# ---- 5. 报告 ----
report_utilization  -file [file join $RPT 10_util.rpt]
report_timing_summary -file [file join $RPT 20_timing.rpt] -warn_on_violation
report_drc          -file [file join $RPT 30_drc.rpt]
report_methodology  -file [file join $RPT 40_methodology.rpt]

set bit [glob -nocomplain [file join $PROJDIR ${PROJ}.runs impl_1 *.bit]]
puts "==== BIT: $bit"
puts "==== DONE ===="