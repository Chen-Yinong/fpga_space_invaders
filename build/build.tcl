# =============================================================================
#  build/build.tcl —— 从零一键重建 + 综合 + 实现 + bitstream + 报告导出
#  器件: 野火升腾Pro XC7A100T-FGG484-2 (xc7a100tfgg484-2)
#  顶层: top_cam_game（光流手势版）
#
#  用法（仓库根目录）:
#      vivado -mode batch -source build/build.tcl
#
#  产出:
#      build/report/*.rpt                 综合/实现/时序/功耗/DRC 报告
#      build/report/00_metrics.txt        关键指标汇总
#      build/cam_game/.../impl_1/*.bit    bitstream
#
#  切换按键版（无摄像头演示）: 把 TOP 改 top_button_game、XDCF 改 top_button_game.xdc
# =============================================================================

set PART  xc7a100tfgg484-2
set TOP   top_cam_game
set XDCF  top_cam_game.xdc
set PROJ  cam_game

# ---- 路径 ----
set SCRIPT   [file normalize [info script]]
set ROOT     [file normalize [file join [file dirname $SCRIPT] ..]]
set SRCDIR   [file join $ROOT src]
set CAMDIR   [file join $ROOT src board_cam]
set HDMIDIR  [file join $ROOT src board_hdmi]
set CONSDIR  [file join $ROOT board]
set BUILDDIR [file join $ROOT build]
set PROJDIR  [file join $BUILDDIR $PROJ]
set RPT      [file join $BUILDDIR report]
file mkdir $RPT

puts "== ROOT: $ROOT"
puts "== PART: $PART   TOP: $TOP"

# ---- 1. 建工程 ----
create_project -force $PROJ $PROJDIR -part $PART

set srcs [glob -nocomplain -directory $SRCDIR   -types f *.sv]
lappend srcs {*}[glob -nocomplain -directory $CAMDIR  -types f *.v]
lappend srcs {*}[glob -nocomplain -directory $HDMIDIR -types f *.v]
if {[llength $srcs] == 0} { error "src/ 下没有找到源文件" }
add_files -fileset sources_1 $srcs
set_property top $TOP [current_fileset]

set xdc [file join $CONSDIR $XDCF]
if {![file exists $xdc]} { error "找不到约束文件: $xdc" }
add_files -fileset constrs_1 $xdc

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
update_compile_order -fileset sources_1

# ---- 3. 综合 ----
puts "== 综合中 ..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "综合失败，见 $PROJDIR/$PROJ.runs/synth_1/runme.log"
}
open_run synth_1 -name synth_1
report_utilization    -file [file join $RPT 10_synth_utilization.rpt]
report_timing_summary -file [file join $RPT 11_synth_timing_summary.rpt]
report_power          -file [file join $RPT 12_synth_power.rpt]
report_drc            -file [file join $RPT 13_synth_drc.rpt]

# ---- 4. 实现 + bitstream ----
puts "== 实现中 ..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "实现失败，见 $PROJDIR/$PROJ.runs/impl_1/runme.log"
}
open_run impl_1
report_utilization    -file [file join $RPT 20_impl_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
                      -file [file join $RPT 21_impl_timing_summary.rpt]
report_clocks         -file [file join $RPT 22_clocks.rpt]
report_route_status   -file [file join $RPT 23_route_status.rpt]
report_power          -file [file join $RPT 24_impl_power.rpt]
report_drc            -file [file join $RPT 25_impl_drc.rpt]

# ---- 5. 指标汇总 ----
proc safe_get {cmd default} {
    if {[catch {uplevel 1 $cmd} res]} { return $default }
    return $res
}
set fh [open [file join $RPT 00_metrics.txt] w]
puts $fh "==== $PROJ 构建指标（布线后）===="
puts $fh "时间: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fh "器件: $PART   顶层: $TOP"
puts $fh ""
puts $fh "WNS(ns) : [safe_get {get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]} N/A]"
puts $fh "WHS(ns) : [safe_get {get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]} N/A]"
puts $fh "LUT     : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ LUT*}]} N/A]"
puts $fh "FF      : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ FD*}]} N/A]"
puts $fh "BRAM    : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]} N/A]"
puts $fh "DSP     : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ DSP*}]} N/A]"
puts $fh ""
puts $fh "时钟:"
foreach c [get_clocks -quiet *] { puts $fh "  $c  period=[safe_get [list get_property PERIOD $c] 0] ns" }
puts $fh ""
puts $fh "bitstream:"
foreach b [glob -nocomplain [file join $PROJDIR $PROJ.runs impl_1 *.bit]] { puts $fh "  $b" }
close $fh

puts "== 完成。报告: $RPT"