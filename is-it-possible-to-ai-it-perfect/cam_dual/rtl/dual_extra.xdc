# 双模式版专用约束（board/top_cam_game.xdc 之外的补充）
#
# 1) key0 = V17（板上第 1 个按键，低有效）——原 XDC 只约束了 key2/key3
set_property IOSTANDARD LVCMOS33 [get_ports key0]
set_property PACKAGE_PIN  V17    [get_ports key0]

# 2) sys_clk -> cam1_pclk 的准静态模式位
#    mode_flow 由 key0 在 sys_clk 域翻转，经 m1/m2 两级同步器进入 cam1_pclk 域
#    原 XDC 只有 cam1_pclk -> sys_clk 的 set_false_path，反向缺失，
#    工具会按“单周期 0.004ns”分析这条跨域路径（实测 -2.932ns）。
#    两级同步器已保证亚稳态收敛，这里按跨域例外处理。
set_false_path -from [get_clocks sys_clk] -to [get_clocks cam1_pclk]