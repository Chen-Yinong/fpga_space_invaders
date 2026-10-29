// ============================================================================
// tb_game_core.sv —— 逐行注释版（原文件 85 行）★ 游戏本体的"自动化体检"
// 这是个 testbench（测试台）：它不综合进 FPGA，只在仿真器里跑，
// 自己模拟按键、模拟时钟，然后一条条断言"现在的状态对不对"。
// 关键手法：TICK_DIV(10) —— 把游戏节拍从 833333 改成 10，
//          于是 60Hz 的游戏逻辑变成"几拍走一次"，仿真几百微秒就能跑完几局。
// ============================================================================
// tb_game_core.sv — 按键版游戏本体功能仿真                                      // 标题：只测 game_core，不含摄像头/光流
`timescale 1ns/1ps                                                      // 仿真时间单位 1ns、精度 1ps
module tb_game_core;                                                    // testbench 没有端口
  localparam int PSLOTS=6, ESLOTS=6, BUNKERS=4;                          // 常量：与 DUT 默认参数一致（6 我方子弹、6 敌方子弹、4 个掩体）
  logic clk_sys=0, rst_n=0;                                              // 信号：系统时钟（初值 0）、复位（初值 0=复位中）
  logic btn_left=0, btn_right=0, btn_start=0, btn_restart=0;             // 信号：四个按键输入，先都给 0（不按）
  logic [8:0]  player_x; logic player_visible;                            // 信号：观察 DUT 输出的炮台位置、是否可见
  logic [PSLOTS-1:0]   pb_valid; logic [PSLOTS*9-1:0] pb_x, pb_y;         // 信号：我方子弹——每槽 1 位有效 + 9 位 x + 9 位 y，压成一个大向量
  logic [ESLOTS-1:0]   eb_valid; logic [ESLOTS*9-1:0] eb_x, eb_y;         // 信号：敌方子弹，结构同上
  logic [54:0] enemy_alive; logic [8:0] enemy_x0, enemy_y0;               // 信号：55 只敌人谁还活着 + 队形左上角坐标
  logic [BUNKERS*24*12-1:0] bunker_bits;                                  // 信号：掩体位图，4×24×12 = 1152 位，1 表示这个像素还在
  logic [15:0] score; logic [3:0] lives; logic [1:0] state;               // 信号：分数、生命、游戏状态机当前状态
  logic ufo_active; logic [8:0] ufo_x;                                    // 信号：UFO 是否出现、它的 x 坐标
  logic win;                                                              // 信号：是否通关
  logic [1:0] stage; logic stage_show, stage_blink;                       // 信号：当前第几关、过关字幕显示中、字幕闪烁

  game_core #(.TICK_DIV(10), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) dut (.*);   // 例化被测模块：TICK_DIV 改成 10 让游戏"快进"，.* 表示同名信号自动连线

  always #5 clk_sys = ~clk_sys;                                           // 每 5ns 翻转一次 → 周期 10ns → 100MHz 仿真时钟
  integer errors=0;                                                       // 变量：失败次数（最后据此判断全过还是失败）
  logic ufo_seen = 1'b0;                                                  // 变量：UFO 是否曾经出现过（粘住不复位）
  always @(posedge clk_sys) if (ufo_active) ufo_seen <= 1'b1;             // 每个时钟沿检查：UFO 只要闪过一次就记下来

  task automatic wait_ticks(input int n); repeat(n) repeat(10) @(negedge clk_sys); endtask   // 任务：等 n 个游戏节拍（1 拍 = 10 个时钟）
  task automatic check(input logic c, input string m);                    // 任务：断言 + 打印
    if (c) $display("[PASS] %s", m);                                       //   条件成立 → 打印 PASS
    else begin $display("[FAIL] %s", m); errors=errors+1; end              //   不成立 → 打印 FAIL 并累加错误数
  endtask                                                                 //   任务结束

  initial begin                                                           // 主流程（只在仿真开始时跑一次）
    repeat(5) @(negedge clk_sys); rst_n=1'b1; repeat(5) @(negedge clk_sys);   // 先按住复位 5 拍，再松开复位，等 5 拍让电路稳定

    check(state==2'd0, "reset -> IDLE");                                   // 断言：复位后处于 IDLE（0）
    check(lives==4'd6, "reset -> lives=6");                                // 断言：复位后 6 条命
    check(enemy_alive=={55{1'b1}}, "reset -> 55 enemies");                 // 断言：复位后 55 只敌人全部存活
    check(bunker_bits=={1152{1'b1}}, "reset -> bunkers full");             // 断言：复位后掩体完整（1152 位全 1）
    check(stage==2'd1, "reset -> stage=1");                                // 断言：复位后从第 1 关开始

    btn_start=1'b1; wait_ticks(3); btn_start=1'b0; wait_ticks(2);          // 模拟按一下开始键（按 3 拍再松开，等 2 拍）
    check(state==2'd1, "start -> PLAY");                                   // 断言：进入 PLAY（1）状态
    check(win==1'b0, "in play -> win=0");                                  // 断言：刚开始时还没赢

    wait_ticks(20);                                                        // 空等 20 拍，让自动开火机制动起来
    check(pb_valid != {PSLOTS{1'b0}}, "auto-fire -> player bullets");      // 断言：我方子弹槽里至少有一个有效（自动开火生效）

    begin                                                                  // 左移测试（用 begin/end 包一块，里面有局部变量）
      logic [8:0] p0; p0=player_x;                                         //   记下移动前的 x
      btn_left=1'b1; wait_ticks(10); btn_left=1'b0; wait_ticks(2);         //   按住左键 10 拍后松开
      check(player_x < p0, "left -> player moved left");                   //   断言：x 变小了
    end                                                                    //   块结束
    begin                                                                  // 右移测试
      logic [8:0] p1; p1=player_x;                                         //   记下当前 x
      btn_right=1'b1; wait_ticks(10); btn_right=1'b0; wait_ticks(2);       //   按住右键 10 拍后松开
      check(player_x > p1, "right -> player moved right");                 //   断言：x 变大了
    end                                                                    //   块结束

    begin                                                                  // 打中外星人测试
      int g=0; while (score==0 && g<400) begin wait_ticks(1); g=g+1; end    //   最多等 400 拍，直到分数不再为 0
    end                                                                    //   块结束
    check(score>0, "hit enemy -> score up");                               // 断言：分数涨了（子弹打中了）

    begin                                                                  // 敌方开火测试
      int g=0; while (eb_valid=={ESLOTS{1'b0}} && g<200) begin wait_ticks(1); g=g+1; end   //   最多等 200 拍直到出现敌方子弹
    end                                                                    //   块结束
    check(eb_valid != {ESLOTS{1'b0}}, "enemy fired bullets");              // 断言：敌人确实开火了

    begin                                                                  // UFO 测试
      int g=0; while (!ufo_seen && g<500) begin wait_ticks(1); g=g+1; end   //   最多等 500 拍直到 UFO 出现
    end                                                                    //   块结束
    check(ufo_seen, "ufo spawned by LFSR");                                // 断言：随机发生器确实让 UFO 出现过

    begin                                                                  // 被击中测试
      int g=0; while (lives==4'd6 && g<2500) begin wait_ticks(1); g=g+1; end   //   最多等 2500 拍直到掉命
    end                                                                    //   块结束
    check(lives<4'd6, "enemy bullet hit -> lives down");                   // 断言：生命减少了

    if (errors==0) $display("\n==== TB_GAME ALL PASS ====");               // 汇总：全部通过
    else           $display("\n==== TB_GAME FAILED: %0d ====", errors);    // 汇总：有几条失败
    $finish;                                                               // 结束仿真
  end                                                                      // initial 结束

  initial begin                                                           // 看门狗：防止仿真卡死
    #200000000; $display("TIMEOUT"); $finish;                              //   200ms 还没结束就打印 TIMEOUT 强行收工
  end                                                                      // initial 结束
endmodule                                                               // testbench 结束
