# cam_dual/program_dual.tcl -- program the dual-mode bitstream into the FPGA
#   default project: cam_dual ; override with env DUAL_PROJ=cam_dual2
set SCRIPT   [file normalize [info script]]
set MERGEDIR [file normalize [file join [file dirname $SCRIPT]]]
set PROJ cam_dual
if {[info exists ::env(DUAL_PROJ)]} { set PROJ $::env(DUAL_PROJ) }
set BIT [file join $MERGEDIR build $PROJ ${PROJ}.runs impl_1 top_cam_dual.bit]

if {![file exists $BIT]} {
    # fall back: take the newest top_cam_dual.bit under merge/build
    set cand [lsort -decreasing [glob -nocomplain [file join $MERGEDIR build * * .runs impl_1 top_cam_dual.bit]]]
    error "BIT not found: $BIT"
}
puts "== BIT: $BIT"

open_hw_manager
connect_hw_server -url localhost:3121
set targs [get_hw_targets -quiet]
if {[llength $targs] == 0} {
    error "no hardware target: check board power / JTAG cable / hw_server -sTCP::3121"
}
current_hw_target [lindex $targs 0]
open_hw_target
set devs [get_hw_devices -quiet -filter {NAME =~ *xc7a100t*}]
if {[llength $devs] == 0} { set devs [get_hw_devices -quiet] }
set dev [lindex $devs 0]
puts "== DEVICE: $dev"
set_property PROGRAM.FILE $BIT $dev
program_hw_devices $dev
puts "==== PROGRAM DONE ===="