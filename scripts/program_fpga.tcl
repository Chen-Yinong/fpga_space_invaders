open_hw_manager
disconnect_hw_server -quiet
connect_hw_server
open_hw_target
puts "==== 设备: [get_hw_devices] ===="
if {[llength [get_hw_devices]] > 0} {
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    set_property PROGRAM.FILE {D:/fpga/fpga_space_invaders/build/fpga_space_invaders/fpga_space_invaders.runs/impl_1/top_cam_game.bit} $dev
    program_hw_devices $dev
    puts "==== 烧写完成 ===="
} else {
    puts "==== 没有检测到 FPGA ===="
}