open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE {D:/fpga/fpga_space_invaders/fpga_space_invaders/fpga_space_invaders.runs/impl_1/top_cam_test.bit} $dev
program_hw_devices $dev
puts "==== PROGRAMMED ===="