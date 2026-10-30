# =============================================================================
#  build_optiflow_reports.tcl —— 光流版（cam_game_optiflowverison）重新构建 + 报告导出
#  用法（仓库根目录）:
#      vivado -mode batch -source 说明/scripts/build_optiflow_reports.tcl
#  产出: build/report/*.rpt + 00_metrics.txt（官方提交结构内）
# =============================================================================
set root [pwd]
set opt  [file join $root is-it-possible-to-ai-it-perfect cam_game_optiflowverison]
set rpt  [file join $root build report]
file mkdir $rpt

puts "== 打开工程: $opt\\cam_game.xpr"
open_project [file join $opt cam_game.xpr]
puts "== 器件: [get_property PART [current_project]]   顶层: [get_property TOP [current_fileset]]"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "SYNTH FAILED" }
open_run synth_1 -name synth_1
report_utilization    -file [file join $rpt 10_synth_utilization.rpt]
report_timing_summary -file [file join $rpt 11_synth_timing_summary.rpt]
report_power          -file [file join $rpt 12_synth_power.rpt]
report_drc            -file [file join $rpt 13_synth_drc.rpt]

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

proc safe_get {cmd default} {
    if {[catch {uplevel 1 $cmd} res]} { return $default }
    return $res
}
set fh [open [file join $rpt 00_metrics.txt] w]
puts $fh "==== cam_game_optiflowverison 构建指标（布线后）===="
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
foreach c [get_clocks -quiet *] { puts $fh "  $c  period=[safe_get [list get_property PERIOD $c] 0] ns" }
puts $fh ""
puts $fh "bitstream:"
foreach b [glob -nocomplain [file join $opt cam_game.runs impl_1 *.bit]] { puts $fh "  $b" }
close $fh
puts "==== DONE ===="