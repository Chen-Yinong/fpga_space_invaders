# button_game

野火「升腾 Pro」XC7A100T-FGG484 独立小工程：按键控制版太空侵略者，HDMI 黑白二色输出。

## 手势控制版（已接线）

顶层 `src/rtl/top_cam_game.sv` 把 Lucas-Kanade 光流手势模块接进了游戏本体：

- 向左挥手 -> 炮台左移（`led_left` 亮）
- 向右挥手 -> 炮台右移（`led_right` 亮）
- 手停 -> 炮台不动（`led_stop` 亮）
- key2（AA18）：开始 / 暂停 / 继续
- key3（AB18）：重开

手势链路复用 `hand_leftorright_for-new-try` 的光流模块（`lk_flow` + `flow_fsm` 等），
`led_left/led_right` 经 2FF 同步后接到 `game_core` 的 `btn_left/btn_right`。HDMI 输出游戏画面。

重建手势版工程：

```powershell
vivado -mode batch -source create_project_cam.tcl
```

（原按键版顶层 `top_button_game.sv` 与 `create_project.tcl` 保留，可随时回退。）

## 操作

- key0（V17）：炮台左移
- key1（W17）：炮台右移
- key2（AA18）：开始 / 暂停 / 继续
- key3（AB18）：重开

## 玩法（按团队最终需求）

- 底部激光炮台自动连射，仅需左右移动
- 6 条生命，数字显示在左上角，0 时游戏结束
- 5 行 × 11 列共 55 只外星人，每只 10 分，左右移动、触边下移掉头
- 外星人随机投弹，命中炮台扣一条命
- 4 座可破坏掩体，挡双方子弹，被击中局部缺口；外星人降落会碾碎掩体
- 任意外星人触底判负
- 左上角计分，初始 000

## 目录

```
button_game/
├── create_project.tcl
├── src/rtl/
│   ├── top_button_game.sv
│   ├── game_core.sv
│   ├── sprite_render.sv
│   ├── debounce.sv
│   ├── vga_timing.sv
│   └── board_hdmi/          # HDMI 芯片 I2C 配置
├── constraints/top_button_game.xdc
└── sim/tb_game_core.sv
```

## 重建工程

```powershell
vivado -mode batch -source create_project.tcl
```

## 仿真

```powershell
vlib work
vlog -sv src/rtl/game_core.sv sim/tb_game_core.sv
vsim -c -do "run -all; quit -f" tb_game_core
```
