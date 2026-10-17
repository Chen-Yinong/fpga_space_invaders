set root [pwd]
open_project [file join $root fpga_space_invaders fpga_space_invaders.xpr]
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "SYNTH FAILED" }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "IMPL FAILED" }
puts "==== DONE ===="