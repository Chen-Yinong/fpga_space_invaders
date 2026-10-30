# =============================================================================
#  build_and_reports.tcl —— 一键构建 + 导出综合/实现报告（提交用）
#  用法（在仓库根目录 D:\fpga\fpga_space_invaders 下执行）:
#      vivado -mode batch -source 说明/scripts/build_and_reports.tcl
#  产出:
#      说明/build_report/*.rpt            综合/实现/时序/功耗/DRC 报告（可提交）
#      说明/build_report/00_metrics.txt   关键指标汇总
#      fpga_space_invaders/.../impl_1/*.bit
# =============================================================================

set root [pwd]
set prj  [file join $root fpga_space_invaders fpga_space_invaders.xpr]
set rpt  [file join $root 说明 build_report]
file mkdir $rpt

puts "== 打开工程: $prj"
open_project $prj

# ---- 综合 ----
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "SYNTH FAILED" }
open_run synth_1 -name synth_1
report_utilization    -file [file join $rpt 10_synth_utilization.rpt]
report_timing_summary -file [file join $rpt 11_synth_timing_summary.rpt]
report_power          -file [file join $rpt 12_synth_power.rpt]
report_drc            -file [file join $rpt 13_synth_drc.rpt]

# ---- 实现 + bitstream ----
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "IMPL FAILED" }
open_run impl_1
report_utilization    -file [file join $rpt 20_impl_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
                      -file [file join $rpt 21_impl_timing_summary.rpt]
report_clocks         -file [file join $rpt 22_clocks.rpt]
report_route_status   -file [file join $rpt 23_route_status.rpt]
report_power          -file [file join $rpt 24_impl_power.rpt]
report_drc            -file [file join $rpt 25_impl_drc.rpt]

# ---- 指标汇总 ----
proc safe_get {cmd default} {
    if {[catch {uplevel 1 $cmd} res]} { return $default }
    return $res
}
set fh [open [file join $rpt 00_metrics.txt] w]
puts $fh "==== fpga_space_invaders 构建指标（布线后）===="
puts $fh "时间: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fh "器件: [get_property PART [current_project]]   顶层: [get_property TOP [current_fileset]]"
puts $fh ""
puts $fh "WNS(ns) : [safe_get {get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]} N/A]"
puts $fh "WHS(ns) : [safe_get {get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]} N/A]"
puts $fh "LUT     : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ LUT*}]} N/A]"
puts $fh "FF      : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ FD*}]} N/A]"
puts $fh "BRAM    : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]} N/A]"
puts $fh "DSP     : [safe_get {llength [get_cells -hier -filter {REF_NAME =~ DSP*}]} N/A]"
puts $fh ""
puts $fh "时钟:"
foreach c [get_clocks -quiet *] {
    puts $fh "  $c  period=[safe_get [list get_property PERIOD $c] 0] ns"
}
puts $fh ""
puts $fh "bitstream:"
foreach b [glob -nocomplain [file join $root fpga_space_invaders fpga_space_invaders.runs impl_1 *.bit]] {
    puts $fh "  $b"
}
close $fh

puts "==== DONE ===="