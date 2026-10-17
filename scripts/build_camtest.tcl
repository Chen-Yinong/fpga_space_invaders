# build_camtest.tcl — 构建摄像头预览调试工程（OV7725）
set root [pwd]
open_project [file join $root build fpga_space_invaders fpga_space_invaders.xpr]
add_files -fileset sources_1 [list \
    [file join $root src rtl cam_preview.sv] \
    [file join $root src rtl top_cam_test.sv] \
    [file join $root src rtl board cam ov7725_top.v] \
    [file join $root src rtl board cam ov7725_cfg.v] \
    [file join $root src rtl board cam ov7725_data.v] ]
set_property top top_cam_test [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "SYNTH FAILED" }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "IMPL FAILED" }
puts "==== DONE ===="