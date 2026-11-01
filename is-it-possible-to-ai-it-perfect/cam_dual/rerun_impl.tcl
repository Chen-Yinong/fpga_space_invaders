# cam_dual/rerun_impl.tcl —— 只重跑实现（复用已有 synth_1 网表），用于约束修改后验证时序
# 用法（仓库根目录，DUAL_PROJ 指向已有工程目录名，默认 cam_dual2）:
#   DUAL_PROJ=cam_dual2 vivado.bat -mode batch -source is-it-possible-to-ai-it-perfect/cam_dual/rerun_impl.tcl
set SCRIPT   [file normalize [info script]]
set MERGEDIR [file normalize [file join [file dirname $SCRIPT]]]
set PROJ cam_dual2
if {[info exists ::env(DUAL_PROJ)]} { set PROJ $::env(DUAL_PROJ) }
set PROJDIR  [file join $MERGEDIR build $PROJ]
set RPT      [file join $MERGEDIR build report]

open_project [file join $PROJDIR ${PROJ}.xpr]

# 清掉已删除的旧约束文件，加入新的补充约束
foreach f [get_files -of [get_filesets constrs_1]] {
    if {![file exists $f]} { puts "== drop missing constraint: $f"; remove_files -fileset constrs_1 $f }
}
set extra [file join $MERGEDIR rtl dual_extra.xdc]
if {[lsearch -exact [get_files -of [get_filesets constrs_1]] $extra] < 0} {
    add_files -fileset constrs_1 $extra
}
puts "== constrs: [get_files -of [get_filesets constrs_1]]"

reset_run impl_1
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
report_utilization    -file [file join $RPT 10_util.rpt]
report_timing_summary -file [file join $RPT 20_timing.rpt]
report_drc            -file [file join $RPT 30_drc.rpt]
set bit [glob -nocomplain [file join $PROJDIR ${PROJ}.runs impl_1 *.bit]]
puts "==== BIT: $bit"
puts "==== DONE ===="