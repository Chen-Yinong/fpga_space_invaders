# build_bitstream.tcl — 综合 + 实现 + 生成比特流
# 用法：cd 到仓库根目录，vivado -mode batch -source scripts/build_bitstream.tcl
set root [pwd]
open_project [file join $root build fpga_space_invaders fpga_space_invaders.xpr]

puts "==== [1/2] 综合 synth_1 ===="
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "SYNTH FAILED"
}

puts "==== [2/2] 实现 + 写比特流 impl_1 ===="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "IMPLEMENTATION FAILED"
}

set bits [glob -nocomplain [file join $root build fpga_space_invaders fpga_space_invaders.runs impl_1 *.bit]]
puts "==== 完成 ===="
puts "比特流文件: $bits"