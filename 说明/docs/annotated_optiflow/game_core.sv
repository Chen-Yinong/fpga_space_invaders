// ============================================================================
// game_core.sv —— 太空侵略者（Space Invaders）游戏核心逻辑【逐行注释版】
// 本文件是源码的"注释副本"：逻辑一行未改，只在每行末尾加了中文说明。
// 源文件：cam_game_optiflowverison/src/rtl/game_core.sv
// ============================================================================
// 【这个模块是干什么的】
//   它只管"游戏规则"，不管"怎么画"。按 60Hz 的节拍推进游戏，然后把"谁在哪、活没活、
//   掩体烂成什么样、得了多少分"用一组扁平信号送出去，由 sprite_render 模块负责画到
//   640x480 的 HDMI 画面上。内部分辨率 320x240，显示时横竖各放大 2 倍，
//   所以本文件里所有坐标都是 0..319 / 0..239。
//
// 【输入从哪来】
//   clk_sys        : 50MHz 系统时钟，所有 always_ff 都跟着它走。
//   rst_n          : 低电平有效复位，把游戏拉回待机。
//   btn_left/right : 左右移动键。来自 debounce 模块（消抖 250000 拍 = 5ms），
//                    送进来的是"稳定电平"，不是脉冲，所以可以按住不放连续移动。
//   btn_start      : 开始 / 暂停键，同一个键在不同状态下含义不同。
//   btn_restart    : 重开键，任何状态下按下都立刻从第 1 关重来。
//
// 【输出到哪去】
//   player_x / player_visible : 玩家战机位置、是否可见（受伤闪烁时灭）。
//   pb_valid / pb_x / pb_y    : PSLOTS(=6) 个玩家子弹槽，每槽 9 位 x、9 位 y，拼成大向量传出。
//   eb_valid / eb_x / eb_y    : ESLOTS(=6) 个敌方子弹槽，拼接方式一样。
//   enemy_alive               : 11*5 = 55 位存活位图，id = 行号*11 + 列号。
//   enemy_x0 / enemy_y0       : 敌人整个队形"左上角"的坐标（队形整体平移，不是每只单独动）。
//   bunker_bits               : 4*24*12 = 1152 位掩体位图，1 表示这格还有土。
//   score / lives / state / win : 分数、生命、2 位状态、胜利标志。
//   ufo_active / ufo_x        : 神秘飞碟在不在场、飞到哪了。
//   stage / stage_show / stage_blink : 第几关、是否正在放过关字幕、字幕闪烁位。
//
// 【状态机只有 4 个状态】(state 是 2 位)
//   S_IDLE  = 2'd0  待机，显示标题，等 start 键
//   S_PLAY  = 2'd1  游戏中，所有游戏动作都在这个状态里跑
//   S_PAUSE = 2'd2  暂停，画面冻住，再按 start 继续
//   S_OVER  = 2'd3  结束，靠 win=1/0 区分"通关"还是"失败"
//
// 【内部关键机制】
//   1) 60Hz 节拍：TICK_DIV = 833333，50MHz/833333 ≈ 60Hz。游戏逻辑只在 tick=1 的那一拍
//      才动，这样游戏速度和显示器刷新率彻底解耦。
//   2) 6 个玩家子弹槽 + 6 个敌方子弹槽：槽位池管理。要发射就找第一个空槽，
//      飞出屏幕就释放槽位，所以最多同时 6 发，槽满了就打不出来。
//   3) 敌人 55 只，队形整体平移：每隔 MOVE_PERIOD 个 tick 平移 2 像素，
//      碰到左右边界就反向并整体下落 8 像素（越来越近，压迫感就是这么来的）。
//   4) 4 个掩体，每个 24x12，按"位"存储：被打中不是整个消失，而是把相关那几列像素凿掉，
//      所以掩体会越打越破——这是原版 Space Invaders 的精髓。
//   5) 生命值：初始 6 条，中弹扣 1 条并进入 60 tick（1 秒）无敌闪烁，归零即失败。
//   6) 波次（关卡）：共 3 关，每关的移动速度 / 投弹频率 / 射速靠查表切换，
//      第 3 关全灭就通关。
//   7) 计分：每只外星人 10 分；击落 UFO 随机 50/100/150/300 分。
// ============================================================================
// game_core.sv — 按键控制版太空侵略者游戏本体  // 文件抬头：这是游戏逻辑本体，不含显示
// 内部坐标 320x240（HDMI 显示 640x480 时 2x 放大）  // 定下坐标系：全部按 320x240 算，输出端再放大 2 倍
// 修复：解耦 1152 位掩体动态寻址，彻底根治 Timing Optimization 综合卡死问题  // 这句是历史遗留：以前用 1152 位大向量的动态下标，Vivado 综合会卡死，所以改成拆分寻址
`timescale 1ns/1ps  // 仿真时间单位 1ns、精度 1ps，只影响仿真，不影响综合
// 空行：模块声明前的分隔
module game_core #(  // 模块名 game_core，后面 #(...) 是参数表，例化时可以改这些数值
  parameter int TICK_DIV    = 833333,   // 50MHz -> 60Hz  // 分频系数：50_000_000/60≈833333，数满这么多个时钟就产生一个 tick，把 50MHz 变成 60Hz
  parameter int PSLOTS      = 6,  // 玩家子弹槽数量：屏幕上最多同时存在 6 发玩家子弹
  parameter int ESLOTS      = 6,  // 敌方子弹槽数量：最多同时 6 发敌人子弹
  parameter int FORM_COLS   = 11,  // 敌人队形 11 列（原版就是 11 列，一排 11 只）
  parameter int FORM_ROWS   = 5,  // 敌人队形 5 行，11*5=55 只外星人
  parameter int LIVES_INIT  = 6,  // 初始生命 6 条（原版 3 条，这里放宽了，更好上手）
  parameter int BUNKERS     = 4,  // 掩体数量 4 个，均匀分布在玩家上方
  parameter int BUNK_W      = 24,  // 每个掩体宽 24 像素
  parameter int BUNK_H      = 12  // 每个掩体高 12 像素，24*12=288 位/个，4 个共 1152 位
)(  // 参数表结束，下面开始端口表
  input  logic clk_sys,  // 50MHz 系统时钟，整个设计的主时钟
  input  logic rst_n,  // 复位，低电平有效（按下为 0，松手为 1）
  input  logic btn_left,  // 左移键，来自 debounce 模块的稳定电平，按住就一直往左走
  input  logic btn_right,  // 右移键，同上
  input  logic btn_start,  // 开始/暂停键：待机或结束时开始游戏，游戏中则暂停/继续
  input  logic btn_restart,  // 重开键：任何时刻按下都清盘，从第 1 关第 6 条命重来
  output logic [8:0]  player_x,  // 玩家战机的 x 坐标（9 位，因为 0..319 要 9 位才装得下）
  output logic        player_visible,  // 玩家是否要画出来：受伤无敌期间会闪烁，就是靠这个信号时有时无
  output logic [PSLOTS-1:0]   pb_valid,  // 6 个玩家子弹槽的"有效"标志，第 i 位为 1 表示第 i 槽有子弹在飞
  output logic [PSLOTS*9-1:0] pb_x,  // 6 个子弹的 x 坐标拼成 54 位，第 i 发占 [9*i+8 : 9*i]
  output logic [PSLOTS*9-1:0] pb_y,  // 6 个子弹的 y 坐标，拼接方式同上
  output logic [ESLOTS-1:0]   eb_valid,  // 6 个敌方子弹槽的有效位
  output logic [ESLOTS*9-1:0] eb_x,  // 敌方子弹 x 坐标拼接（9 位一发）
  output logic [ESLOTS*9-1:0] eb_y,  // 敌方子弹 y 坐标拼接
  output logic [FORM_COLS*FORM_ROWS-1:0] enemy_alive,  // 55 位存活位图：第 (行*11+列) 位为 0 表示那只外星人已被打死
  output logic [8:0]  enemy_x0,  // 敌人队形左上角的 x：注意是"整个队形"的原点，不是某一只的坐标
  output logic [8:0]  enemy_y0,  // 敌人队形左上角的 y
  output logic [BUNKERS*BUNK_W*BUNK_H-1:0] bunker_bits,  // 1152 位掩体位图：第 b 个掩体、第 yy 行、第 xx 列对应位下标 b*288+yy*24+xx，1=有土
  output logic [15:0] score,  // 当前分数，16 位，最大能显示 65535 分
  output logic [3:0]  lives,  // 剩余生命，4 位（0..15），到 0 就 Game Over
  output logic [1:0]  state,  // 当前状态，取值见下面 S_IDLE / S_PLAY / S_PAUSE / S_OVER
  output logic        win,  // 结束时是赢还是输：1=通关（打完第 3 关），0=失败
  output logic        ufo_active,  // 神秘飞碟是否正在屏幕上横飞
  output logic [8:0]  ufo_x,  // 飞碟的 x 坐标（从左边 0 往右飞）
  output logic [1:0]  stage,  // 第几关，1/2/3 关
  output logic        stage_show,  // 是否正在放"过关"过渡画面（进入下一关前闪 2 秒字幕）
  output logic        stage_blink  // 过关字幕的闪烁位，渲染端用它做一亮一灭的效果
);  // 端口表结束
  localparam logic [1:0] S_IDLE=2'd0, S_PLAY=2'd1, S_PAUSE=2'd2, S_OVER=2'd3;  // 状态编码：0 待机、1 游戏中、2 暂停、3 结束，用 localparam 是为了后面写代码可读

  localparam int CELL_W=14, CELL_H=10, COL_GAP=18, ROW_GAP=14;  // 外星人单体尺寸 14x10 像素；列间距 18（含 4 像素空隙）、行间距 14（含 4 像素空隙）
  localparam int FORM_W = (FORM_COLS-1)*COL_GAP + CELL_W;   // 194  // 队形总宽：(11-1)*18+14 = 194 像素，这是判断"撞没撞到右边界"的依据
  localparam int X_MIN = 2;  // 队形左边界最小 2 像素，留一点边不贴死屏幕
  localparam int X_MAX = 320 - FORM_W - 2;                   // 124  // 队形左边界最大 320-194-2=124：x0 到 124 时队形右边缘刚好到 318，再往右就出屏了
  localparam int FORM_STEP = 2;  // 队形每次左右平移 2 像素（速度感由此而来）
  localparam int FORM_DROP = 8;  // 队形撞到边界后向下落 8 像素，一步一步逼近玩家
  localparam int ENEMY_X0_INI = 40;  // 开局队形左上角的 x：40，居中偏左，看起来比较平衡
  localparam int ENEMY_Y0_INI = 40;  // 开局队形左上角的 y：40，在屏幕上方
  localparam int MOVE_PERIOD = 25;  // 队形每 25 个 tick 才动一次：60Hz 下约 0.42 秒挪 2 像素，慢悠悠地压过来
  localparam int PB_PERIOD = 15;    // 自动连射间隔(tick, 60Hz)  // 玩家自动射击间隔 15 tick = 0.25 秒一发，即每秒 4 发
  localparam int EB_PERIOD = 30;  // 敌人投弹间隔 30 tick = 0.5 秒一发（第 1 关的基础值）
  localparam int PB_SPEED = 5;  // 玩家子弹每 tick 上移 5 像素，很快，打出去立刻见效果
  localparam int EB_SPEED = 3;  // 敌人子弹每 tick 下移 3 像素，比玩家子弹慢，给玩家闪避时间
  localparam int PLAYER_SPEED = 2;  // 玩家左右移动速度：每 tick 2 像素
  localparam int PLAYER_HALF = 8;  // 玩家战机半宽 8 像素（机体宽 16），碰撞检测就用 ±8
  localparam int PX_MIN = PLAYER_HALF;  // 玩家能到的最左位置 8：再往左机身就缺一角出屏了
  localparam int PX_MAX = 320 - PLAYER_HALF;  // 玩家能到的最右位置 312，同理
  localparam int PLAYER_Y = 220;  // 玩家战机所在高度 y=220，靠近屏幕底部（240 高的下面 20 行）
  localparam int INV_FRAMES = 60;  // 中弹后的无敌时间 60 tick = 1 秒，期间玩家闪烁且不掉血
  localparam int BUNK_Y = 180;  // 掩体顶边 y=180，位于玩家(220)上方 40 像素处
  localparam int UFO_SPEED = 4;          // 每 tick 4 像素，较快  // 飞碟横向速度：每 tick 4 像素，横穿屏幕只要 80 tick
  localparam int UFO_Y = 24, UFO_W = 20, UFO_H = 8;   // 顶端横飞  // 飞碟贴顶飞：y=24，尺寸 20x8，所以碰撞框就是这 20x8
  localparam int UFO_SPAWN_MIN = 200;    // 最小触发间隔(tick)  // 两次飞碟之间至少隔 200 tick ≈ 3.3 秒，再随机加 0~2047
  localparam int STAGE_CLEAR_TICKS = 120; // 过关过渡时长(2 秒)  // 过关字幕显示 120 tick = 2 秒，之后才切下一关
  function automatic [8:0] get_bunk_x(input int b);// ---- 修正：严谨固定坐标映射（防止数组下标倒置）----  // 查第 b 个掩体的左边界 x：直接用 case 写死，不用乘法/数组，避免综合出奇怪的下标
    case (b)  // 根据掩体编号挑坐标
      0: return 9'd32;  // 第 0 个掩体在 x=32
      1: return 9'd108;  // 第 1 个在 x=108
      2: return 9'd184;  // 第 2 个在 x=184
      default: return 9'd260;  // 第 3 个（及兜底）在 x=260，四个掩体大致把 320 宽三等分着摆开
    endcase  // case 结束
  endfunction  // get_bunk_x 函数结束

  // ---- 60Hz tick ----  // 分节：先把 50MHz 时钟降成 60Hz 的游戏节拍
  logic [31:0] tick_cnt; logic tick;  // tick_cnt 是分频计数器，tick 是"这一拍到了"的单周期脉冲
  always_ff @(posedge clk_sys or negedge rst_n)  // 时序逻辑：时钟上升沿触发，复位异步低有效
    if (!rst_n) begin tick_cnt<='0; tick<=1'b0; end  // 复位：计数器清零，tick 拉低
    else if (tick_cnt >= TICK_DIV-1) begin tick_cnt<='0; tick<=1'b1; end  // 数到 833332 就归零并拉高 tick，产生一个 60Hz 脉冲
    else begin tick_cnt<=tick_cnt+1'b1; tick<=1'b0; end  // 平时一直加 1，tick 保持 0

  // ---- 按键边沿 / 计数器 ----  // 分节：按键上一拍的值和各种倒计时计数器
  logic btn_start_d, btn_restart_d;  // 记录 start/restart 上一拍的按键值，用来做"上升沿"检测（按下的那一瞬间）
  logic [7:0] pb_cnt, eb_cnt, inv_cnt;  // pb_cnt:玩家射击倒计时 eb_cnt:敌人投弹倒计时 inv_cnt:玩家无敌倒计时
  logic [15:0] move_cnt;  // 敌人移动倒计时（比 8 位大，因为周期值可到 25，留足余量）
  logic dir;  // 敌人队形移动方向：0=向右、1=向左
  logic [15:0] lfsr;  // 16 位线性反馈移位寄存器，当伪随机数用（选发弹列、UFO 出现时机与分值）
  logic        stage_clear;  // "正在过关过渡"标志：为 1 时游戏暂停推进，只放字幕
  logic [7:0]  stage_clear_cnt;  // 过关过渡的倒计时，数到 120 就切下一关

  // ---- 关卡难度参数（外星人移动/投弹加快，末关玩家射速上调、投弹放慢）----  // 分节：三关难度表
  logic [7:0] mv_period, eb_period, pb_period, pb_speed;  // 本关的移动周期、投弹周期、射击周期、子弹速度，全部用寄存器存，避免长组合路径
  always_comb begin  // 组合逻辑：stage 一变，这四个参数立刻跟着变，不用等时钟
    case (stage)  // 按关卡号查表
      2'd2: begin mv_period=8'd20; eb_period=8'd24; pb_period=8'd15; pb_speed=8'd5; end  // 第 2 关：敌人挪得更勤(20)、投弹更密(24)，玩家射速不变
      2'd3: begin mv_period=8'd15; eb_period=8'd40; pb_period=8'd10; pb_speed=8'd7; end  // 第 3 关：敌人移动最快(15)，但投弹反而变慢(40)给玩家喘息；玩家射速翻倍(10)、子弹更快(7)
      default: begin mv_period=8'd25; eb_period=8'd30; pb_period=8'd15; pb_speed=8'd5; end  // 第 1 关（以及意外值）：基础难度，就是上面那组 localparam 的值
    endcase  // 查表结束
  end  // always_comb 结束

  // ---- 空闲子弹槽 ----  // 分节：找第一个空槽，用于新发射的子弹
  logic [3:0] pb_free; logic pb_found;  // pb_free 是找到的空槽号，pb_found 表示到底有没有空槽
  always_comb begin  // 组合逻辑：槽位占用情况一变，结果立刻更新，发射时就能用到最新值
    pb_found=1'b0; pb_free=4'd0;  // 先把"没找到"和槽号 0 作为默认值，避免锁存器
    for (int i=0;i<PSLOTS;i++) if (!pb_found && !pb_valid[i]) begin pb_found=1'b1; pb_free=i[3:0]; end  // 从 0 号槽往上扫，碰到第一个空的就记住并停止（优先级编码，等价于一个 6 选 1 的优先编码器）
  end  // 结束
  logic [3:0] eb_free; logic eb_found;  // 敌方子弹的空槽号 / 是否找到，逻辑完全同上
  always_comb begin  // 组合逻辑
    eb_found=1'b0; eb_free=4'd0;  // 默认值
    for (int i=0;i<ESLOTS;i++) if (!eb_found && !eb_valid[i]) begin eb_found=1'b1; eb_free=i[3:0]; end  // 同样扫第一个空槽
  end  // 结束

  // ---- 列/行坐标预计算（寄存，缩短碰撞路径）----  // 分节：把每列左边界、每行上边界提前算好存起来
  logic [8:0] col_lx [0:FORM_COLS-1];  // col_lx[c] = 第 c 列外星人的左边 x（= enemy_x0 + c*18）
  logic [8:0] row_ty [0:FORM_ROWS-1];  // row_ty[r] = 第 r 行外星人的上边 y（= enemy_y0 + r*14）
  always_ff @(posedge clk_sys or negedge rst_n)  // 时序逻辑，用寄存器而不是纯组合，是为了把"乘法/加法"从碰撞判断的关键路径里挪出来
    if (!rst_n) begin  // 复位
      for (int c=0;c<FORM_COLS;c++) col_lx[c] <= 9'd0;  // 11 列的左边界全部清零
      for (int r=0;r<FORM_ROWS;r++) row_ty[r] <= 9'd0;  // 5 行的上边界全部清零
    end else if (tick) begin  // 只在 tick 那一拍更新，60Hz 更新一次足够，省得每拍都算
      for (int c=0;c<FORM_COLS;c++) col_lx[c] <= enemy_x0 + c*COL_GAP;  // 第 c 列左边界 = 队形原点 + c 个列间距
      for (int r=0;r<FORM_ROWS;r++) row_ty[r] <= enemy_y0 + r*ROW_GAP;  // 第 r 行上边界 = 队形原点 + r 个行间距
    end  // 更新结束

  // ---- 玩家子弹 x 外星人碰撞（组合，浅层）----  // 分节：判断每一发玩家子弹打中了哪只外星人
  logic [PSLOTS-1:0] pb_hit_c;  // 组合结果：第 i 位为 1 表示第 i 发子弹这一拍打中了外星人
  logic [6:0] pb_idx_c [PSLOTS];  // 组合结果：第 i 发子弹打中的是第几只外星人（0..54，7 位够用）
  always_comb begin  // 纯组合判断，用寄存器化过的列/行坐标查表，所以层级很浅
    for (int i=0;i<PSLOTS;i++) begin  // 6 发子弹逐个查
      pb_hit_c[i]=1'b0; pb_idx_c[i]=7'd0;  // 先假设这一发没打中
      if (pb_valid[i]) begin  // 只有真的在飞的子弹才需要算
        for (int r=0;r<FORM_ROWS;r++) for (int c=0;c<FORM_COLS;c++) begin  // 55 只外星人逐个比（5 行 x 11 列）
          automatic int id = r*FORM_COLS+c;  // 这只外星人在存活位图里的编号：行*11+列
          automatic int ex = col_lx[c];  // 它所在列的左边界（查预计算表）
          automatic int ey = row_ty[r];  // 它所在行的上边界
          automatic int bx = pb_x[9*i +: 9];  // 取出第 i 发子弹的 x（用 +: 做向量切片，9*i 是起始位）
          automatic int by = pb_y[9*i +: 9];  // 取出第 i 发子弹的 y
          if (!pb_hit_c[i] && enemy_alive[id] &&  // 还没打中过（保证只记第一只）+ 这只还活着
              bx >= ex && bx < ex+CELL_W && by >= ey && by < ey+CELL_H) begin  // 子弹点落在 14x10 的机身矩形里就算命中
            pb_hit_c[i] = 1'b1;  // 标记这一发命中了
            pb_idx_c[i] = id[6:0];  // 记住打中的是哪一只，之后要把它从存活位图里清掉
          end  // 命中判断结束
        end  // 55 只循环结束
      end  // 子弹有效判断结束
    end  // 6 发循环结束
  end  // always_comb 结束

  // ---- 碰撞结果寄存一级 ----  // 分节：把上面的组合结果打一拍再使用
  logic [PSLOTS-1:0] pb_hit;  // 打过一拍的命中标志
  logic [6:0] pb_idx [PSLOTS];  // 打过一拍的命中编号
  always_ff @(posedge clk_sys or negedge rst_n)  // 每个时钟都打一拍（不只是 tick），保证命中信息不丢
    if (!rst_n) begin  // 复位
      pb_hit<='0;  // 命中标志全清
      for (int i=0;i<PSLOTS;i++) pb_idx[i]<=7'd0;  // 编号也全清
    end else begin  // 正常工作时
      pb_hit<=pb_hit_c;  // 组合结果延时一拍变正式结果
      for (int i=0;i<PSLOTS;i++) pb_idx[i]<=pb_idx_c[i];  // 编号同样延时一拍
    end  // 结束（代价是命中晚 1 拍生效，好处是把长组合路径切断，时序好收敛）

  // ---- 命中计分（每只 10 分）----  // 分节：算这一拍要加多少分
  logic [15:0] score_delta;  // 本拍的得分增量
  always_comb begin  // 组合逻辑
    score_delta=16'd0;  // 默认 0 分
    for (int i=0;i<PSLOTS;i++) if (pb_hit[i]) score_delta=score_delta+16'd10;  // 每有一发子弹命中就加 10 分（同一拍打中两只就加 20）
  end  // 结束

  // ---- 敌弹 x 玩家碰撞 ----  // 分节：判断敌人子弹有没有打到玩家
  logic eb_hit_any;  // 这一拍是否有敌弹打到玩家（打到就掉一条命）
  always_comb begin  // 组合逻辑
    eb_hit_any=1'b0;  // 默认没打中
    if (inv_cnt==8'd0) begin  // 只有不在无敌状态时才判定，否则无敌期间等于免伤
      for (int i=0;i<ESLOTS;i++) begin  // 6 发敌弹逐个查
        automatic int ex = eb_x[9*i +: 9];  // 取出这发敌弹的 x
        automatic int ey = eb_y[9*i +: 9];  // 取出这发敌弹的 y
        if (eb_valid[i] && ex >= player_x-PLAYER_HALF && ex < player_x+PLAYER_HALF &&  // 子弹 x 落在玩家机体左右 ±8 之内
            ey >= PLAYER_Y-12 && ey < PLAYER_Y+2)  // 子弹 y 落在玩家高度 208..221 之间（战机高度约 14 像素，判定框略紧一点更公平）
          eb_hit_any=1'b1;  // 命中，标记掉血
      end  // 6 发循环结束
    end  // 无敌判断结束
  end  // always_comb 结束

  // ---- 敌机发射者（随机列的最底存活行）----  // 分节：决定这一发敌弹从哪一列、哪一行打出来
  logic [3:0] rnd_col;  // 随机选中的列号（0..10）
  always_comb rnd_col = (lfsr[3:0] >= 4'd11) ? (lfsr[3:0]-4'd11) : lfsr[3:0];  // 用 LFSR 低 4 位取"模 11"：≥11 就减 11，得到 0..10 的列号（省一个除法器）
  logic [2:0] shooter_row; logic shooter_ok;  // shooter_row 是开火的那一行，shooter_ok 表示这一列还有活人能开火
  always_comb begin  // 组合逻辑
    shooter_ok=1'b0; shooter_row=3'd0;  // 默认：没人能开火
    for (int r=FORM_ROWS-1; r>=0; r--) begin  // 从最后一行（最靠近玩家）往上扫
      if (!shooter_ok && enemy_alive[r*FORM_COLS + rnd_col]) begin  // 找到这一列最下面的活人
        shooter_ok=1'b1; shooter_row=r[2:0];  // 记下它，后面的行就不用管了（所以每列只有最底那只开火，符合原版规则）
      end  // 判断结束
    end  // 行循环结束
  end  // always_comb 结束

  // ---- 辅助函数：提取指定掩体 b、局部列 lx 的 12 位纵向像素状态 ----  // 分节：读掩体位图里"某一竖列"的 12 个像素
  function automatic logic [BUNK_H-1:0] get_bunk_col(input int b, input logic [4:0] lx);  // 输入掩体号 b 和掩体内局部列号 lx，返回这一列 12 个像素的"有土/没土"状态
    logic [BUNK_H-1:0] col_bits;  // 临时变量：装这 12 位的纵向像素
    col_bits = '0;  // 先全清零，防止没赋值的位综合出锁存器
    for (int yy = 0; yy < BUNK_H; yy++) begin  // 从顶部第 0 行扫到第 11 行
      if (lx < BUNK_W)  // 列号必须落在 0..23 之内才算合法，防越界
        col_bits[yy] = bunker_bits[b*BUNK_W*BUNK_H + yy*BUNK_W + int'(lx)];  // 一位一位搬出来：第 b 个掩体的基址 + 行偏移 + 列号
    end  // 行循环结束
    return col_bits;  // 返回这一列的 12 位像素状态
  endfunction  // 函数结束

  // ---- 玩家子弹撞掩体检测（仅当该列对应高度仍有掩体像素时才触发）----  // 分节：玩家子弹打掩体
  logic [PSLOTS-1:0] pb_bhit;  // 第 i 位为 1 表示第 i 发玩家子弹撞上掩体了
  logic [1:0] pb_bid [PSLOTS];  // 撞的是第几个掩体（0..3，2 位）
  logic [4:0] pb_blx [PSLOTS];  // 撞点在掩体内部的列号 lx（0..23，5 位）
  logic [3:0] pb_bly [PSLOTS];  // 撞点在掩体内部的行号 ly（0..11，4 位）
  always_comb begin  // 组合逻辑
    for (int i=0; i<PSLOTS; i++) begin  // 6 发子弹逐个查
      pb_bhit[i]=1'b0; pb_bid[i]=2'd0; pb_blx[i]=5'd0; pb_bly[i]=4'd0;  // 默认都没撞
      if (pb_valid[i]) begin  // 只有在飞的子弹才需要查
        automatic int bx = pb_x[9*i +: 9];  // 这发子弹的 x
        automatic int by = pb_y[9*i +: 9];  // 这发子弹的 y
        for (int b=0; b<BUNKERS; b++) begin  // 4 个掩体逐个查
          automatic int bx_base = get_bunk_x(b);  // 这个掩体的左边界
          if (!pb_bhit[i] && (bx >= bx_base) && (bx < bx_base + BUNK_W) &&  // 子弹 x 落在这个掩体的 24 像素宽之内
              (by >= BUNK_Y) && (by < BUNK_Y + BUNK_H)) begin  // 子弹 y 落在这个掩体的 12 像素高之内
            automatic logic [4:0] lx = 5'(bx - bx_base);  // 换算成掩体内部列号
            automatic logic [3:0] ly = 4'(by - BUNK_Y);  // 换算成掩体内部行号
            automatic logic [BUNK_H-1:0] col_bits = get_bunk_col(b, lx);  // 取出这一列的 12 位状态
            // 补偿 PB_SPEED=5 步长：若 ly<=2 则顺带检查顶边 yy=0..1，只有存在像素(1'b1)才判定碰撞  // 因为子弹一拍走 5 像素，可能一步跨过薄土，所以要往前多看一点
            automatic logic [3:0] check_y = (ly <= 4'd2) ? 4'd0 : ly;  // 靠近顶部时把碰撞行压到 0，等于把上面几格一起纳入判断，防隧穿
            if ((col_bits >> check_y) != '0) begin  // 从 check_y 行往下还有没有土？有才真的算撞上（掩体已经被打空了就穿过去）
              pb_bhit[i] = 1'b1;  // 记录撞上了
              pb_bid[i]  = b[1:0];  // 记住是哪个掩体
              pb_blx[i]  = lx;  // 记住列号
              pb_bly[i]  = check_y;  // 记住行号（凿洞从这里开始往下）
            end  // 判定结束
          end  // 掩体范围判断结束
        end  // 4 个掩体循环结束
      end  // 子弹有效判断结束
    end  // 6 发循环结束
  end  // always_comb 结束

  // ---- 敌弹撞掩体检测（仅当该列对应高度仍有掩体像素时才触发）----  // 分节：敌人子弹打掩体
  logic [ESLOTS-1:0] eb_bhit;  // 第 i 位为 1 表示第 i 发敌弹撞上掩体
  logic [1:0] eb_bid [ESLOTS];  // 撞的是第几个掩体
  logic [4:0] eb_blx [ESLOTS];  // 撞点列号
  logic [3:0] eb_bly [ESLOTS];  // 撞点行号
  always_comb begin  // 组合逻辑
    for (int i=0; i<ESLOTS; i++) begin  // 6 发敌弹逐个查
      eb_bhit[i]=1'b0; eb_bid[i]=2'd0; eb_blx[i]=5'd0; eb_bly[i]=4'd0;  // 默认都没撞
      if (eb_valid[i]) begin  // 只有活着的敌弹才算
        automatic int ex = eb_x[9*i +: 9];  // 敌弹 x
        automatic int ey = eb_y[9*i +: 9];  // 敌弹 y
        for (int b=0; b<BUNKERS; b++) begin  // 4 个掩体逐个查
          automatic int bx_base = get_bunk_x(b);  // 掩体左边界
          if (!eb_bhit[i] && (ex >= bx_base) && (ex < bx_base + BUNK_W) &&  // x 在掩体宽度范围内
              (ey >= BUNK_Y) && (ey < BUNK_Y + BUNK_H)) begin  // y 在掩体高度范围内
            automatic logic [4:0] lx = 5'(ex - bx_base);  // 换算成内部列号
            automatic logic [3:0] ly = 4'(ey - BUNK_Y);  // 换算成内部行号
            automatic logic [BUNK_H-1:0] col_bits = get_bunk_col(b, lx);  // 这一列的 12 位像素
            // 检查从顶边 0 到 ly+2 范围内是否还有未销毁的掩体像素  // 敌弹是往下走的，会砸塌上面一截，所以要往下多看 2 行
            automatic logic [3:0] hit_end = (ly + 4'd2 >= BUNK_H) ? 4'(BUNK_H-1) : (ly + 4'd2);  // 往下多看 2 行，但不能超过第 11 行，超了就夹到 11
            if ((col_bits & ((12'h1 << (hit_end + 1'b1)) - 12'h1)) != '0) begin  // 造一个 0..hit_end 的低位掩码再与：这段里只要还有土就算撞上
              eb_bhit[i] = 1'b1;  // 记录撞上
              eb_bid[i]  = b[1:0];  // 记掩体号
              eb_blx[i]  = lx;  // 记列号
              eb_bly[i]  = hit_end;  // 记砸到的最深行（凿洞到这里为止）
            end  // 判定结束
          end  // 范围判断结束
        end  // 掩体循环结束
      end  // 敌弹有效判断结束
    end  // 敌弹循环结束
  end  // always_comb 结束

  // ---- 提取本帧击中掩体的子弹坐标（化简为单事件，彻底消灭 1152 位 MUX）----  // 分节：把"6 发子弹里谁撞了掩体"压成唯一一个事件
  logic       pb_hit_bunker_en;  // 本拍是否有玩家子弹撞掩体（只看第一个撞的）
  logic [1:0] pb_hit_bid;  // 撞的掩体号
  logic [4:0] pb_hit_lx;  // 撞点列号
  logic [3:0] pb_hit_ly;  // 撞点行号
  always_comb begin  // 组合逻辑
    pb_hit_bunker_en = 1'b0;  // 默认没有
    pb_hit_bid       = 2'd0;  // 默认掩体 0
    pb_hit_lx        = 5'd0;  // 默认列 0
    pb_hit_ly        = 4'd0;  // 默认行 0
    for (int i=0; i<PSLOTS; i++) begin  // 扫 6 发子弹，取第一个撞上的
      if (!pb_hit_bunker_en && pb_bhit[i]) begin  // 还没选中过、且这发撞了
        pb_hit_bunker_en = 1'b1;  // 锁定本次事件
        pb_hit_bid       = pb_bid[i];  // 搬运掩体号
        pb_hit_lx        = pb_blx[i];  // 搬运列号
        pb_hit_ly        = pb_bly[i];  // 搬运行号
      end  // 结束（这么做的好处：后面改掩体位图时只需面对一套坐标，而不是 6 套，硬件省一大半）
    end  // 循环结束
  end  // always_comb 结束

  logic       eb_hit_bunker_en;  // 本拍是否有敌弹撞掩体
  logic [1:0] eb_hit_bid;  // 掩体号
  logic [4:0] eb_hit_lx;  // 列号
  logic [3:0] eb_hit_ly;  // 行号
  always_comb begin  // 和上面完全对称的一套逻辑，只是换成敌弹
    eb_hit_bunker_en = 1'b0;  // 默认没有
    eb_hit_bid       = 2'd0;  // 默认掩体 0
    eb_hit_lx        = 5'd0;  // 默认列 0
    eb_hit_ly        = 4'd0;  // 默认行 0
    for (int i=0; i<ESLOTS; i++) begin  // 扫 6 发敌弹
      if (!eb_hit_bunker_en && eb_bhit[i]) begin  // 取第一个撞上的
        eb_hit_bunker_en = 1'b1;  // 锁定事件
        eb_hit_bid       = eb_bid[i];  // 搬运掩体号
        eb_hit_lx        = eb_blx[i];  // 搬运列号
        eb_hit_ly        = eb_bly[i];  // 搬运行号
      end  // 结束
    end  // 循环结束
  end  // always_comb 结束

  wire alien_crush = (enemy_y0 + (FORM_ROWS-1)*ROW_GAP + CELL_H >= BUNK_Y);  // 外星人队形最下面一行的底边压到掩体顶边(180)时，"碾碎"信号成立，掩体被整片刮掉
  assign player_visible = (inv_cnt==8'd0) | inv_cnt[4];  // 玩家闪烁：无敌倒计时为 0 时常亮；否则用第 4 位当闪烁位，大约 16 tick 亮一次、16 tick 灭一次

  // ---- 神秘飞碟（LFSR 随机触发 + 随机大奖）----  // 分节：UFO 的分值表和碰撞
  logic        ufo_active_r;  // 飞碟是否在场的寄存器版本（后面 assign 到输出）
  logic [8:0]  ufo_x_r;  // 飞碟的 x 坐标寄存器
  logic [15:0] ufo_spawn_cnt;  // 距离下次飞碟出现的倒计时
  logic [8:0]  ufo_pts;  // 这次打掉飞碟能得多少分
  always_comb case (lfsr[1:0])  // 用 LFSR 最低 2 位当"抽奖"：四种结果
    2'd0: ufo_pts = 9'd50;  // 1/4 概率只给 50 分（低保）
    2'd1: ufo_pts = 9'd100;  // 1/4 概率 100 分
    2'd2: ufo_pts = 9'd150;  // 1/4 概率 150 分
    default: ufo_pts = 9'd300;  // 1/4 概率 300 分（大奖）
  endcase  // 抽奖结束（分值在飞碟出现的整个过程中会随 lfsr 变化，命中那一拍取到什么就是什么）

  logic [PSLOTS-1:0] ufo_hit_pb;  // 哪几发玩家子弹这一拍打中了飞碟
  always_comb begin  // 组合逻辑
    for (int i=0;i<PSLOTS;i++) begin  // 6 发子弹逐个查
      ufo_hit_pb[i] = ufo_active_r && pb_valid[i] &&  // 飞碟必须在场、子弹必须有效
        (pb_x[9*i +: 9] >= ufo_x_r) && (pb_x[9*i +: 9] < ufo_x_r + UFO_W) &&  // 子弹 x 落在飞碟 20 像素宽度内
        (pb_y[9*i +: 9] >= UFO_Y) && (pb_y[9*i +: 9] < UFO_Y + UFO_H);  // 子弹 y 落在飞碟 8 像素高度内
    end  // 循环结束
  end  // always_comb 结束
  logic ufo_hit_any;  // 这一拍有没有打中飞碟
  always_comb ufo_hit_any = |ufo_hit_pb;  // 把 6 位或起来：任意一发命中就是命中
  assign ufo_active = ufo_active_r;  // 内部寄存器直连输出端口
  assign ufo_x = ufo_x_r;  // 同上
  assign stage_show = stage_clear;  // 过关过渡标志直接给渲染端，用于显示半透明字幕
  assign stage_blink = stage_clear_cnt[4];  // 闪烁位取倒计时的第 4 位：每 16 tick 翻转一次，字幕就一亮一灭

  // ---- 主状态机与时序逻辑 ----  // 分节：整个游戏的核心 always_ff，下面所有动作都在这里
  always_ff @(posedge clk_sys or negedge rst_n) begin  // 时钟上升沿触发、异步复位，一个块里写完了状态机和全部游戏动作
    if (!rst_n) begin  // 复位分支：把游戏恢复到待机初始状态
      state          <= S_IDLE;  // 回到待机
      player_x       <= 9'd160;  // 玩家摆屏幕正中（320/2）
      pb_valid       <= '0;  // 6 发玩家子弹全部清空
      pb_x           <= '0;  // 子弹 x 坐标清零
      pb_y           <= '0;  // 子弹 y 坐标清零
      eb_valid       <= '0;  // 敌弹全部清空
      eb_x           <= '0;  // 敌弹 x 清零
      eb_y           <= '0;  // 敌弹 y 清零
      enemy_alive    <= {FORM_COLS*FORM_ROWS{1'b1}};  // 55 只外星人全部复活（全 1），复制语法 55{1'b1}
      enemy_x0       <= ENEMY_X0_INI[8:0];  // 队形回到初始 x=40（截 9 位）
      enemy_y0       <= ENEMY_Y0_INI[8:0];  // 队形回到初始 y=40
      bunker_bits    <= '1;  // 1152 位掩体全部填满，4 个掩体完好无损
      score          <= '0;  // 分数从 0 开始
      lives          <= LIVES_INIT[3:0];  // 生命 6 条（参数转 4 位）
      move_cnt       <= '0;  // 敌人移动倒计时清零
      dir            <= 1'b0;  // 队形初始向右移动
      pb_cnt         <= '0;  // 射击倒计时清零
      eb_cnt         <= '0;  // 投弹倒计时清零
      inv_cnt        <= '0;  // 无敌倒计时清零（开局不无敌）
      btn_start_d    <= 1'b0;  // 按键历史清零，避免复位后误判成"刚按下"
      btn_restart_d  <= 1'b0;  // 同上
      lfsr           <= 16'hACE1;  // 伪随机种子，取个有点"乱"的初值，避免每次上电序列都一模一样
      win            <= 1'b0;  // 胜利标志清零
      stage          <= 2'd1;  // 从第 1 关开始
      stage_clear    <= 1'b0;  // 不在过关过渡中
      stage_clear_cnt<= 8'd0;  // 过渡倒计时清零
      ufo_active_r   <= 1'b0;  // 飞碟不在场
      ufo_x_r        <= 9'd0;  // 飞碟位置归零
      ufo_spawn_cnt  <= UFO_SPAWN_MIN[15:0];  // 飞碟倒计时装 200，开局约 3.3 秒后第一次出现
    end else if (tick) begin  // 正常工作时，只有 60Hz 的 tick 那一拍才往前走（这就是游戏节拍）
      btn_start_d   <= btn_start;  // 把这一拍的 start 键存起来，下一拍就能比较出"上升沿"
      btn_restart_d <= btn_restart;  // 同理
      lfsr          <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};  // 16 位 LFSR 走一步：整体左移，新最低位由 16/14/13/11 位异或得到（最大长度序列，伪随机够用）
      if (inv_cnt != 0) inv_cnt <= inv_cnt - 1'b1;  // 无敌倒计时递减，减到 0 就恢复可被击中

      if (btn_restart & ~btn_restart_d) begin  // 重开键"刚按下"的上升沿：任何状态都立刻重开
        // 重开  // 下面这一大段就是把整个游戏清盘回初始状态
        state       <= S_PLAY;  // 直接进游戏（不用再按 start）
        player_x    <= 9'd160;  // 玩家回中间
        pb_valid    <= '0;  // 清空玩家子弹
        eb_valid    <= '0;  // 清空敌弹
        enemy_alive <= {FORM_COLS*FORM_ROWS{1'b1}};  // 55 只外星人全部复活
        enemy_x0    <= ENEMY_X0_INI[8:0];  // 队形回到 x=40
        enemy_y0    <= ENEMY_Y0_INI[8:0];  // 队形回到 y=40
        bunker_bits <= '1;  // 掩体全部修复
        score       <= '0;  // 分数归零
        lives       <= LIVES_INIT[3:0];  // 生命恢复 6 条
        move_cnt    <= '0;  // 移动倒计时清零
        dir         <= 1'b0;  // 初始向右
        pb_cnt      <= '0;  // 射击倒计时清零
        eb_cnt      <= '0;  // 投弹倒计时清零
        inv_cnt     <= '0;  // 无敌清零
        ufo_active_r  <= 1'b0;  // 飞碟撤走
        ufo_x_r       <= 9'd0;  // 飞碟位置归零
        ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0];  // 飞碟倒计时重置
        win           <= 1'b0;  // 胜利标志清掉
        stage         <= 2'd1;  // 回第 1 关
        stage_clear   <= 1'b0;  // 取消过关过渡
        stage_clear_cnt<= 8'd0;  // 过渡倒计时清零
      end  // 重开分支结束
      else if (btn_start & ~btn_start_d) begin  // start 键"刚按下"的上升沿
        if (state==S_IDLE || state==S_OVER) begin  // 待机或结束时按 start：开新一局（动作和重开几乎一样，只是从待机/结束进入）
          state       <= S_PLAY;  // 进入游戏
          player_x    <= 9'd160;  // 玩家回中间
          pb_valid    <= '0;  // 清空玩家子弹
          eb_valid    <= '0;  // 清空敌弹
          enemy_alive <= {FORM_COLS*FORM_ROWS{1'b1}};  // 外星人全复活
          enemy_x0    <= ENEMY_X0_INI[8:0];  // 队形 x 复位
          enemy_y0    <= ENEMY_Y0_INI[8:0];  // 队形 y 复位
          bunker_bits <= '1;  // 掩体修复
          score       <= '0;  // 分数归零
          lives       <= LIVES_INIT[3:0];  // 生命恢复
          move_cnt    <= '0;  // 移动倒计时清零
          dir         <= 1'b0;  // 向右
          pb_cnt      <= '0;  // 射击倒计时清零
          eb_cnt      <= '0;  // 投弹倒计时清零
          inv_cnt     <= '0;  // 无敌清零
          ufo_active_r  <= 1'b0;  // 飞碟撤走
          ufo_x_r       <= 9'd0;  // 飞碟位置归零
          ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0];  // 飞碟倒计时重置
          win           <= 1'b0;  // 胜利标志清掉
          stage         <= 2'd1;  // 回第 1 关
          stage_clear   <= 1'b0;  // 取消过关过渡
          stage_clear_cnt<= 8'd0;  // 过渡倒计时清零
        end else if (state==S_PLAY)  state <= S_PAUSE;  // 游戏中按 start：暂停
        else if (state==S_PAUSE)     state <= S_PLAY;  // 暂停中按 start：继续
      end  // start 键处理结束
      else if (state==S_PLAY) begin  // 只有"游戏中"这一大块才会推进游戏内容
        if (stage_clear) begin  // 如果正在过关过渡
          // 过关过渡：屏幕闪烁显示 Stage N，2 秒后进下一关  // 过渡期游戏冻结，只数倒计时
          if (stage_clear_cnt >= STAGE_CLEAR_TICKS-1) begin  // 数到 119（即已经过 2 秒）
            stage_clear     <= 1'b0;  // 关闭过渡
            stage_clear_cnt <= 8'd0;  // 倒计时归零
            stage           <= stage + 1'b1;  // 关卡号 +1（1→2→3）
            enemy_alive     <= {FORM_COLS*FORM_ROWS{1'b1}};  // 新一关外星人全复活
            enemy_x0        <= ENEMY_X0_INI[8:0];  // 队形 x 回到 40
            enemy_y0        <= ENEMY_Y0_INI[8:0] + stage*FORM_DROP;  // 队形 y 起点随关卡下移：第 2 关 48、第 3 关 56，越后面敌人越近
            bunker_bits     <= '1;  // 掩体修复（每关重新给 4 个完整掩体）
            lives           <= LIVES_INIT[3:0];  // 生命也补满，等于新关重新开始
            pb_valid        <= '0;  // 清空上一关残留的玩家子弹
            eb_valid        <= '0;  // 清空敌弹
            move_cnt        <= '0;  // 移动倒计时清零
            dir             <= 1'b0;  // 重新向右
            pb_cnt          <= '0;  // 射击倒计时清零
            eb_cnt          <= '0;  // 投弹倒计时清零
            inv_cnt         <= '0;  // 无敌清零
          end else begin  // 还没数到 2 秒
            stage_clear_cnt <= stage_clear_cnt + 1'b1;  // 倒计时加 1，字幕继续闪
          end  // 过渡判断结束
        end else begin  // 不处于过渡，正常推进游戏
        // 1. 玩家移动  // ---- 玩家左右移动：按住键就每 tick 走 2 像素，到边界就停 ----
        if (btn_left && player_x > PX_MIN)  // 按左键且还没到最左(8)
          player_x <= player_x - PLAYER_SPEED;  // 向左移动：x 减 2，但不能小于 8，到边就被挡住（上面那个 > PX_MIN 就是限位）
        else if (btn_right && player_x < PX_MAX)  // 否则如果按右键且还没到最右(312)
          player_x <= player_x + PLAYER_SPEED;  // 向右移动：x 加 2，同理不能超过 312

        // 2. 自动连射  // ---- 玩家自动开火：每隔 pb_period 个 tick 打一发，不用玩家按键 ----
        if (pb_cnt >= pb_period-1) begin  // 射击倒计时数满了
          pb_cnt <= '0;  // 倒计时归零，重新数
          if (pb_found) begin  // 有空槽才发得出来，6 发都满了就这一拍不发
            pb_valid[pb_free]           <= 1'b1;  // 占用找到的那个空槽
            pb_x[9*pb_free +: 9]        <= player_x;  // 子弹从玩家当前位置射出（x 跟玩家一致）
            pb_y[9*pb_free +: 9]        <= PLAYER_Y[8:0] - 9'd8;  // 子弹初始 y = 220-8 = 212，即战机头顶上方一点
          end  // 空槽判断结束
        end else begin  // 还没数满
          pb_cnt <= pb_cnt + 1'b1;  // 倒计时继续加
        end  // 射击分支结束

        // 3. 玩家子弹移动与命中销毁  // ---- 6 发玩家子弹：往上飞、飞出屏幕销毁、打中外星人或掩体就销毁 ----
        for (int i=0; i<PSLOTS; i++) begin  // 6 个槽逐个处理
          if (pb_valid[i]) begin  // 这个槽有子弹
            if (pb_y[9*i +: 9] < pb_speed)  // 再往上飞就要飞出屏幕顶了
              pb_valid[i] <= 1'b0;  // 直接销毁（释放槽位）
            else  // 还没到顶
              pb_y[9*i +: 9] <= pb_y[9*i +: 9] - pb_speed;  // 向上移动：y 减去本关的子弹速度（第 3 关是 7）
          end  // 移动结束
          if (pb_hit[i]) begin  // 这一发（延迟一拍后的结果）打中了外星人
            pb_valid[i]            <= 1'b0;  // 子弹消失
            enemy_alive[pb_idx[i]] <= 1'b0;  // 被打中的那只外星人从存活位图里清掉，得 10 分在下面统一加
          end  // 命中处理结束
          if (pb_bhit[i]) begin  // 这一发撞上了掩体
            pb_valid[i] <= 1'b0; // 撞掩体销毁  // 子弹同样消失，掩体的洞在下面第 7 步里凿
          end  // 撞掩体处理结束
        end  // 6 发循环结束
        // UFO 命中：销毁子弹 + 随机大奖  // ---- 打中飞碟：飞碟消失，所有打中它的子弹消失，分数按抽奖加 ----
        if (ufo_hit_any) begin  // 有子弹打中飞碟
          ufo_active_r <= 1'b0;  // 飞碟被打掉
          for (int i=0;i<PSLOTS;i++) if (ufo_hit_pb[i]) pb_valid[i] <= 1'b0;  // 打中飞碟的那几发子弹也一起销毁
        end  // UFO 命中处理结束
        score <= score + score_delta + (ufo_hit_any ? {7'b0, ufo_pts} : 16'd0);  // 一次性结算分数：外星人得分 + （打中飞碟就加抽到的分值，否则加 0）

        // UFO 移动 / 随机触发  // ---- 飞碟在场就右移，飞出去就撤走并重置倒计时；不在场就数倒计时，数到 0 就放出来 ----
        if (ufo_active_r) begin  // 飞碟在场
          if (ufo_x_r + UFO_SPEED > 320) begin  // 再往右就飞出屏幕
            ufo_active_r  <= 1'b0;  // 撤走
            ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0] + {5'b0, lfsr[10:0]};  // 下次出现时间 = 200 + 随机 0..2047，间隔不固定才像随机
          end else begin  // 还在屏内
            ufo_x_r <= ufo_x_r + UFO_SPEED;  // 每 tick 右移 4 像素
          end  // 位置判断结束
        end else begin  // 飞碟不在场
          if (ufo_spawn_cnt == 16'd0) begin  // 倒计时数完了
            ufo_active_r  <= 1'b1;  // 放出飞碟
            ufo_x_r       <= 9'd0;  // 从屏幕最左边出现
            ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0] + {5'b0, lfsr[10:0]};  // 立刻给下一轮重装一个随机倒计时
          end else begin  // 还没数完
            ufo_spawn_cnt <= ufo_spawn_cnt - 1'b1;  // 倒计时减 1
          end  // 计时判断结束
        end  // UFO 分支结束

        // 4. 外星人整体平移与触边下落  // ---- 队形左右平移：撞到左右边界就反向并整体下落 8 像素 ----
        if (move_cnt >= mv_period-1) begin  // 移动倒计时数满（周期由关卡决定：25/20/15）
          move_cnt <= '0;  // 归零重数
          if (!dir) begin  // 当前向右走
            if (enemy_x0 + FORM_STEP > X_MAX) begin  // 再往右一步就超过最大左边界 124
              dir      <= 1'b1;  // 掉头向左
              enemy_y0 <= enemy_y0 + FORM_DROP;  // 同时整体下落 8 像素（撞墙落下，原版规则）
            end else begin  // 还没到右边界
              enemy_x0 <= enemy_x0 + FORM_STEP;  // 整个队形右移 2 像素
            end  // 右边界判断结束
          end else begin  // 当前向左走
            if (enemy_x0 < X_MIN + FORM_STEP) begin  // 再往左一步就小于 4（X_MIN=2 再加一步的量）
              dir      <= 1'b0;  // 掉头向右
              enemy_y0 <= enemy_y0 + FORM_DROP;  // 同样下落 8 像素
            end else begin  // 还没到左边界
              enemy_x0 <= enemy_x0 - FORM_STEP;  // 整个队形左移 2 像素
            end  // 左边界判断结束
          end  // 方向判断结束
        end else begin  // 还没到该动的时刻
          move_cnt <= move_cnt + 1'b1;  // 倒计时加 1
        end  // 移动分支结束

        // 5. 敌机发射子弹  // ---- 敌人投弹：每隔 eb_period 个 tick，从随机列最底下那只外星人打出一发 ----
        if (eb_cnt >= eb_period-1) begin  // 投弹倒计时数满（周期由关卡决定：30/24/40）
          eb_cnt <= '0;  // 归零重数
          if (shooter_ok && eb_found) begin  // 这一列还有活人、并且有空弹槽，才打得出来
            eb_valid[eb_free]    <= 1'b1;  // 占用空槽
            eb_x[9*eb_free +: 9] <= enemy_x0 + rnd_col*COL_GAP + CELL_W/2;  // 弹 x = 队形原点 + 列号*18 + 机宽一半(7)，即从那只外星人的正中间出来
            eb_y[9*eb_free +: 9] <= enemy_y0 + shooter_row*ROW_GAP + CELL_H;  // 弹 y = 队形原点 + 行号*14 + 机高10，即从那架机身下沿出来
          end  // 发射条件结束
        end else begin  // 还没数满
          eb_cnt <= eb_cnt + 1'b1;  // 倒计时加 1
        end  // 投弹分支结束

        // 6. 敌弹移动与命中销毁  // ---- 6 发敌弹往下飞、飞出屏幕底部销毁、撞掩体销毁、打到玩家扣命 ----
        for (int i=0; i<ESLOTS; i++) begin  // 6 个敌弹槽逐个处理
          if (eb_valid[i]) begin  // 这个槽有弹
            if (eb_y[9*i +: 9] > 9'd236)  // 已经掉到 236 以下（屏幕底部 240 附近）
              eb_valid[i] <= 1'b0;  // 飞出屏幕就销毁
            else  // 还在屏内
              eb_y[9*i +: 9] <= eb_y[9*i +: 9] + EB_SPEED;  // 向下移动：y 加 3
          end  // 移动结束
          if (eb_bhit[i]) begin  // 这发敌弹撞上掩体
            eb_valid[i] <= 1'b0; // 撞掩体销毁  // 弹消失，掩体上的坑在下面第 7 步凿
          end  // 撞掩体处理结束
        end  // 敌弹循环结束
        if (eb_hit_any) begin  // 有敌弹打到玩家
          lives   <= lives - 1'b1;  // 生命减 1
          inv_cnt <= INV_FRAMES[7:0];  // 进入 60 tick 无敌，防止同一发弹连续扣命
          for (int i=0; i<ESLOTS; i++) eb_valid[i] <= 1'b0;  // 清空所有敌弹，让玩家有喘息空间（原版也是清屏）
        end  // 掉血处理结束

        // 7. 掩体像素更新（消除隧穿：玩家子弹削底边，敌弹削顶边）  // ---- 掩体被打坏：按位重写 1152 位，被命中的地方凿成 0 ----
        for (int b = 0; b < BUNKERS; b++) begin  // 4 个掩体逐个遍历
          automatic int bx_base = get_bunk_x(b);  // 这个掩体的左边界（屏幕坐标）
          for (int yy = 0; yy < BUNK_H; yy++) begin  // 掩体内 12 行
            for (int xx = 0; xx < BUNK_W; xx++) begin  // 掩体内 24 列，共 4*12*24 = 1152 个像素逐个处理
              automatic int idx = b*BUNK_W*BUNK_H + yy*BUNK_W + xx;  // 这个像素在 1152 位大向量里的下标：掩体基址 + 行偏移 + 列号
              automatic int wx  = bx_base + xx;  // 换算成屏幕上的绝对 x，用来和外星人位置比较

              // 外星人触碰整列碾碎（优先级最高）  // 三种破坏原因按优先级从高到低判断
              if (alien_crush && (wx >= enemy_x0) && (wx < enemy_x0 + FORM_W))  // 队形已经压到掩体高度，并且这一列正好在队形覆盖范围内
                bunker_bits[idx] <= 1'b0;  // 整列清零：外星人碾过的地方全没了
              // 玩家激光向上击中：横向 3 像素，从碰撞点往下打通到底边  // 玩家子弹往上打，会把掩体下半截打穿
              else if (pb_hit_bunker_en && (pb_hit_bid == b[1:0]) &&  // 本拍有玩家子弹撞掩体，且撞的是这个掩体
                       (xx + 1 >= pb_hit_lx) && (xx <= pb_hit_lx + 1) && (yy >= pb_hit_ly))  // 横向 3 格宽（命中列 ±1），纵向从命中行一直到底部
                bunker_bits[idx] <= 1'b0;  // 把这些像素凿掉
                // 敌机炸弹向下砸中：横向 3 像素，从顶边砸到碰撞点  // 敌弹往下砸，会把掩体上半截砸掉
              else if (eb_hit_bunker_en && (eb_hit_bid == b[1:0]) &&  // 本拍有敌弹撞掩体，且是这个掩体
                       (xx + 1 >= eb_hit_lx) && (xx <= eb_hit_lx + 1) && (yy <= eb_hit_ly))  // 横向 3 格宽，纵向从顶边到命中行
                bunker_bits[idx] <= 1'b0;  // 把这些像素凿掉，于是掩体上挖出一个"V"形缺口
            end  // 24 列循环结束
          end  // 12 行循环结束
        end  // 4 个掩体循环结束
        // 空行（源码这里是 8 个空格，留白分隔用）
        // 8. 胜负终局裁决  // ---- 判胜负：没命了/敌人压到玩家了算输，打到第 3 关全灭算赢 ----
        if (lives == 4'd0) begin  // 生命耗尽
          state <= S_OVER;  // 进结束状态
          win   <= 1'b0;  // 失败
        end else if (enemy_y0 + (FORM_ROWS-1)*ROW_GAP + CELL_H >= PLAYER_Y) begin  // 队形最下一行的底边压到玩家所在高度 220（等于敌人已经贴脸）
          state <= S_OVER;  // 直接结束
          win   <= 1'b0;  // 算输（原版就是被外星人攻破防线）
        end else if (enemy_alive == '0) begin  // 55 只外星人全被打光
          if (stage == 2'd3) begin  // 而且已经是在最后一关
            state <= S_OVER;  // 结束
            win   <= 1'b1;  // 通关胜利
          end else begin  // 不是最后一关
            stage_clear     <= 1'b1;  // 进入过关过渡（先闪 2 秒字幕）
            stage_clear_cnt <= 8'd0;  // 过渡倒计时从 0 开始数
          end  // 关卡判断结束
        end  // 胜负判断结束
        end  // 结束"不处于过关过渡"的那个 else 分支（对应上面第 456 行的 end else begin）
      end  // 结束"state==S_PLAY"分支
    end  // 结束"tick 那一拍"分支
  end  // 结束主 always_ff

endmodule  // 模块结束，game_core 到此为止
