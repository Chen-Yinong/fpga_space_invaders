set dcp  "D:/fpga/fpga_space_invaders/is-it-possible-to-ai-it-perfect/cam_game_optiflowverison/cam_game.runs/impl_1/top_cam_game_routed.dcp"
set rpt  "D:/fpga/fpga_space_invaders/build/report"
open_checkpoint $dcp
report_utilization    -file [file join $rpt 20_impl_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 -file [file join $rpt 21_impl_timing_summary.rpt]
report_clocks         -file [file join $rpt 22_clocks.rpt]
report_route_status   -file [file join $rpt 23_route_status.rpt]
report_power          -file [file join $rpt 24_impl_power.rpt]
report_drc            -file [file join $rpt 25_impl_drc.rpt]
set fh [open [file join $rpt 00_metrics.txt] w]
puts $fh "==== cam_game_optiflowverison 构建指标（布线后，DCP 导出）===="
puts $fh "WNS(ns): [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts $fh "WHS(ns): [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]"
puts $fh "LUT: [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]"
puts $fh "FF : [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]"
puts $fh "BRAM: [llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
puts $fh "DSP : [llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]"
foreach c [get_clocks -quiet *] { puts $fh "clock $c  period=[get_property PERIOD $c]" }
close $fh
puts "REPORTS DONE"