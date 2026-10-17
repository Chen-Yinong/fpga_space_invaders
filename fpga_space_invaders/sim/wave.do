# wave.do — 在 ModelSim GUI 里加载波形
# 用法: vsim -gui -do wave.do tb_game_core
add wave -divider "clock/reset"
add wave -position end sim:/tb_game_core/clk_sys
add wave -position end sim:/tb_game_core/rst_n
add wave -divider "buttons"
add wave -position end -radix bin sim:/tb_game_core/btn_left
add wave -position end -radix bin sim:/tb_game_core/btn_right
add wave -position end -radix bin sim:/tb_game_core/btn_start
add wave -position end -radix bin sim:/tb_game_core/btn_fire
add wave -divider "game state"
add wave -position end -radix unsigned sim:/tb_game_core/state
add wave -position end -radix unsigned sim:/tb_game_core/player_x
add wave -position end -radix bin sim:/tb_game_core/bullet_valid
add wave -position end -radix unsigned sim:/tb_game_core/bullet_y
add wave -position end -radix unsigned sim:/tb_game_core/score
add wave -position end -radix hex sim:/tb_game_core/enemy_alive
run -all