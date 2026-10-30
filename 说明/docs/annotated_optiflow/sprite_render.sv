// ============================================================================
// sprite_render.sv —— 逐行注释版（原文件 257 行）★ 纯组合逻辑的"画家"
// 输入：当前扫描点坐标 + 所有游戏对象的位置；输出：这个点该是什么颜色
// 内部坐标 320×240（vid_x[9:1], vid_y[9:1] 把 640×480 缩小一半）
// ============================================================================
// sprite_render.sv — 黑白二色太空侵略者渲染（外星人/玩家/子弹/掩体/HUD）   // 标题
// 内部坐标 320x240，显示 640x480 时 2x 放大                                  // 说明：满屏放大 2 倍
`timescale 1ns/1ps                                                      // 仿真时间精度
module sprite_render #(                                                 // 模块声明 + 参数
  parameter int PSLOTS = 6,                                             // 参数：我方子弹槽数
  parameter int ESLOTS = 6,                                             // 参数：敌方子弹槽数
  parameter int FORM_COLS = 11,                                         // 参数：敌机编队列数
  parameter int FORM_ROWS = 5,                                          // 参数：敌机编队行数
  parameter int BUNKERS = 4                                             // 参数：掩体个数
)(                                                                      // 参数结束
  input  logic [9:0]  vid_x, vid_y,                                     // 输入：当前扫描点坐标（0..639 / 0..479）
  input  logic [8:0]  player_x,                                         // 输入：炮台中心 x
  input  logic        player_visible,                                   // 输入：炮台是否可见（死亡后闪烁）
  input  logic [PSLOTS-1:0]   pb_valid,                                 // 输入：我方子弹有效位
  input  logic [PSLOTS*9-1:0] pb_x,                                     // 输入：我方子弹 x（每发 9 位，打包）
  input  logic [PSLOTS*9-1:0] pb_y,                                     // 输入：我方子弹 y
  input  logic [ESLOTS-1:0]   eb_valid,                                 // 输入：敌弹有效位
  input  logic [ESLOTS*9-1:0] eb_x,                                     // 输入：敌弹 x
  input  logic [ESLOTS*9-1:0] eb_y,                                     // 输入：敌弹 y
  input  logic [FORM_COLS*FORM_ROWS-1:0] enemy_alive,                   // 输入：55 个敌机的存活位图
  input  logic [8:0]  enemy_x0,                                         // 输入：编队左上角 x
  input  logic [8:0]  enemy_y0,                                         // 输入：编队左上角 y
  input  logic [BUNKERS*24*12-1:0] bunker_bits,                         // 输入：掩体像素位图（24×12×4 位）
  input  logic [15:0] score,                                            // 输入：分数
  input  logic [3:0]  lives,                                            // 输入：剩余生命
  input  logic [1:0]  state,                                            // 输入：游戏状态（3=结束）
  input  logic        win,                                              // 输入：是否通关
  input  logic        ufo_active,                                       // 输入：UFO 是否出现
  input  logic [8:0]  ufo_x,                                            // 输入：UFO 的 x
  input  logic [1:0]  stage,                                            // 输入：当前波次
  input  logic        stage_show,                                       // 输入：是否在显示波次提示
  input  logic        stage_blink,                                      // 输入：波次提示是否处于灭的相位
  output logic [23:0] rgb                                               // 输出：该点颜色 RGB888
);                                                                      // 端口结束
  localparam int BUNK_W = 24, BUNK_H = 12, BUNK_Y = 180;                 // 常量：掩体宽 24、高 12、离顶部 180
  localparam int BUNK_X [0:BUNKERS-1] = '{32, 108, 184, 260};            // 常量：4 个掩体的 x 坐标（均匀铺开）
  localparam int CELL_W = 14, CELL_H = 10, COL_GAP = 18, ROW_GAP = 14;   // 常量：敌机本体 14×10，横向间隔 18，纵向间隔 14
  localparam int PLAYER_Y = 220, PLAYER_HALF = 8;                         // 常量：炮台底部 y=220，半宽 8
  localparam int UFO_Y = 24, UFO_W = 20, UFO_H = 8;                       // 常量：UFO 在高度 24，尺寸 20×8

  logic [8:0] gx, gy;                                                    // 内部：缩小后的坐标（内部坐标系）
  assign gx = vid_x[9:1];                                                // 组合：640 → 320（右移 1 位 = 除以 2）
  assign gy = vid_y[8:1];                                                // 组合：480 → 240 上半部分（只取低 9 位再除 2）

  // ---- 8x8 数字字模（bit7 = 最左列）----                                  // 第 1 段：字库
  function automatic logic [7:0] font_row(input logic [3:0] d, input logic [2:0] r);  // 函数：给数字 d 和行号 r，返回这一行的 8 位点阵
    case (d)                                                             //   先按数字选
      4'd0: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h6E; 3'd3:font_row=8'h76; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase  // 数字 0：0x3C=00111100 上横，0x6E/0x76 做出斜杠
      4'd1: case (r) 3'd0:font_row=8'h18; 3'd1:font_row=8'h38; 3'd2:font_row=8'h18; 3'd3:font_row=8'h18; 3'd4:font_row=8'h18; 3'd5:font_row=8'h18; 3'd6:font_row=8'h7E; default:font_row=8'h00; endcase  // 数字 1：上面带个小勾
      4'd2: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h06; 3'd3:font_row=8'h0C; 3'd4:font_row=8'h30; 3'd5:font_row=8'h60; 3'd6:font_row=8'h7E; default:font_row=8'h00; endcase  // 数字 2：右上弯 + 底下长横
      4'd3: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h06; 3'd3:font_row=8'h1C; 3'd4:font_row=8'h06; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase  // 数字 3：两个半圆叠起来
      4'd4: case (r) 3'd0:font_row=8'h0C; 3'd1:font_row=8'h1C; 3'd2:font_row=8'h3C; 3'd3:font_row=8'h6C; 3'd4:font_row=8'h7E; 3'd5:font_row=8'h0C; 3'd6:font_row=8'h0C; default:font_row=8'h00; endcase  // 数字 4：斜线 + 中间横杠
      4'd5: case (r) 3'd0:font_row=8'h7E; 3'd1:font_row=8'h60; 3'd2:font_row=8'h7C; 3'd3:font_row=8'h06; 3'd4:font_row=8'h06; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase  // 数字 5：上横 + 下半圆
      4'd6: case (r) 3'd0:font_row=8'h1C; 3'd1:font_row=8'h30; 3'd2:font_row=8'h60; 3'd3:font_row=8'h7C; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase  // 数字 6：左下开口的小圆圈
      4'd7: case (r) 3'd0:font_row=8'h7E; 3'd1:font_row=8'h66; 3'd2:font_row=8'h0C; 3'd3:font_row=8'h18; 3'd4:font_row=8'h18; 3'd5:font_row=8'h18; 3'd6:font_row=8'h18; default:font_row=8'h00; endcase  // 数字 7：上横 + 斜撇
      4'd8: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h66; 3'd3:font_row=8'h3C; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase  // 数字 8：两个圈
      4'd9: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h66; 3'd3:font_row=8'h3E; 3'd4:font_row=8'h06; 3'd5:font_row=8'h0C; 3'd6:font_row=8'h38; default:font_row=8'h00; endcase  // 数字 9：上圈 + 右下钩
      default: font_row=8'h00;                                           //     其他数字 → 全黑
    endcase                                                              //   数字 case 结束
  endfunction                                                            // 函数结束

  // ---- 8x8 字母/符号字模（bit7 = 最左列）----                              // 第 2 段：字母库
  function automatic logic [7:0] alpha_row(input logic [3:0] code, input logic [2:0] r);  // 函数：给字符编码和行号，返回点阵
    case (code)                                                          //   按字符编码选
      4'd0: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h7E; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h66; default:alpha_row=8'h00; endcase // A
      4'd1: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h60; 3'd4:alpha_row=8'h60; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // C
      4'd2: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h60; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h7C; 3'd4:alpha_row=8'h60; 3'd5:alpha_row=8'h60; 3'd6:alpha_row=8'h7E; default:alpha_row=8'h00; endcase // E
      4'd3: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h6E; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // G
      4'd4: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h7E; default:alpha_row=8'h00; endcase // I
      4'd5: case (r) 3'd0:alpha_row=8'hC6; 3'd1:alpha_row=8'hEE; 3'd2:alpha_row=8'hFE; 3'd3:alpha_row=8'hD6; 3'd4:alpha_row=8'hC6; 3'd5:alpha_row=8'hC6; 3'd6:alpha_row=8'hC6; default:alpha_row=8'h00; endcase // M
      4'd6: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h66; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // O
      4'd7: case (r) 3'd0:alpha_row=8'h7C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h7C; 3'd4:alpha_row=8'h68; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h66; default:alpha_row=8'h00; endcase // R
      4'd8: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h3C; 3'd4:alpha_row=8'h06; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // S
      4'd9: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // T
      4'd10: case (r) 3'd0:alpha_row=8'h66; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h66; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h3C; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // V
      4'd11: case (r) 3'd0:alpha_row=8'h66; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h3C; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // Y
      4'd12: case (r) 3'd0:alpha_row=8'h00; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h00; 3'd4:alpha_row=8'h00; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // :（上下两点）
      4'd13: case (r) 3'd0:alpha_row=8'h18; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h00; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // !（竖线 + 点）
      default: alpha_row=8'h00;                                         //     其他编码 → 全黑
    endcase                                                              //   case 结束
  endfunction                                                            // 函数结束

  // ---- 结束画面字符序列（0=VICTORY! 1=SCORE: 2=GAME OVER）----           // 第 3 段：整词拼装
  function automatic [3:0] word_code(input logic [1:0] w, input int k);  // 函数：给词号 w 和第 k 个字符，返回字符编码
    case (w)                                                             //   按词选
      2'd0: case (k) 0:word_code=4'd10; 1:word_code=4'd4; 2:word_code=4'd1; 3:word_code=4'd9; 4:word_code=4'd6; 5:word_code=4'd7; 6:word_code=4'd11; default:word_code=4'd13; endcase  // "VICTORY!" = V I C T O R Y !
      2'd1: case (k) 0:word_code=4'd8; 1:word_code=4'd1; 2:word_code=4'd6; 3:word_code=4'd7; 4:word_code=4'd2; 5:word_code=4'd12; default:word_code=4'd14; endcase  // "SCORE:" = S C O R E :
      default: case (k) 0:word_code=4'd3; 1:word_code=4'd0; 2:word_code=4'd5; 3:word_code=4'd2; 4:word_code=4'd14; 5:word_code=4'd6; 6:word_code=4'd10; 7:word_code=4'd2; default:word_code=4'd7; endcase  // "GAME OVE"+"R"（共 9 个字符）
    endcase                                                              //   case 结束
  endfunction                                                            // 函数结束

  // ---- 外星人（方头三脚，按行分色）----                                   // 第 4 段：画敌机
  logic hit_enemy, eye;                                                  // 内部：这个点是不是敌机、是不是眼睛
  logic [23:0] enemy_col;                                                // 内部：敌机颜色
  always_comb begin                                                      // 组合逻辑：遍历 55 个敌机
    hit_enemy=1'b0; eye=1'b0; enemy_col=24'hFFFFFF;                       //   默认：不是敌机、白色
    for (int r=0;r<FORM_ROWS;r++) for (int c=0;c<FORM_COLS;c++) begin    //   双重循环：5 行 × 11 列
      automatic int id = r*FORM_COLS+c;                                  //     一维编号
      automatic int ex = enemy_x0 + c*COL_GAP;                           //     这只敌机的左上角 x
      automatic int ey = enemy_y0 + r*ROW_GAP;                           //     这只敌机的左上角 y
      if (enemy_alive[id] && int'(gx)>=ex && int'(gx)<ex+CELL_W && int'(gy)>=ey && int'(gy)<ey+CELL_H) begin  // 活着 且 点落在它的 14×10 范围内
        automatic int lx = int'(gx)-ex;                                  //     局部 x（0..13）
        automatic int ly = int'(gy)-ey;                                  //     局部 y（0..9）
        // 主体（方头）+ 三只脚                                             //     形状说明
        if ((lx>=1 && lx<13 && ly>=0 && ly<6) ||                          //     上 6 行、去掉左右各 1 像素 = 方头
            (ly>=6 && ly<10 && ((lx>=2&&lx<4)||(lx>=6&&lx<8)||(lx>=10&&lx<12)))) begin  //   下 4 行画三条 2 像素宽的腿
          hit_enemy=1'b1;                                                //     命中
          enemy_col = (r==FORM_ROWS-1) ? 24'h5EE7FF : (r>=2) ? 24'hFFFFFF : 24'hFFFF00;  // 颜色：最后一行浅蓝、中间白色、上面黄色
          if ((lx>=4 && lx<6 && ly>=2 && ly<5) || (lx>=8 && lx<10 && ly>=2 && ly<5)) eye=1'b1;  // 两个 2×3 的方块当眼睛
        end                                                              //   形状 if 结束
      end                                                                //   范围 if 结束
    end                                                                  //   循环结束
  end                                                                    //   always_comb 结束

  // ---- 玩家炮台（炮管 + 梯形底座）----                                    // 第 5 段：画炮台
  logic hit_player;                                                      // 内部：这个点是不是炮台
  always_comb begin                                                      // 组合逻辑
    hit_player=1'b0;                                                     //   默认不是
    if (player_visible) begin                                            //   可见时才画（死亡闪烁）
      automatic int dx = int'(gx) - int'(player_x);                      //     相对炮台中心的横向偏移
      automatic int dy = int'(gy) - (PLAYER_Y-10);                       //     相对炮台顶部的纵向偏移
      if ((dy>=0 && dy<=5 && dx>=-1 && dx<=1) ||                          //     上 6 行、宽 3 像素 = 细炮管
          (dy>=5 && dy<10 && dx>=-(3+(dy-5)) && dx<=(3+(dy-5))))          //     下 5 行每行加宽 1 → 梯形底座
        hit_player=1'b1;                                                 //     命中
    end                                                                  //   可见判断结束
  end                                                                    //   always_comb 结束

  // ---- 子弹 ----                                                        // 第 6 段：画子弹
  logic hit_pb, hit_eb;                                                  // 内部：我方/敌方子弹命中
  always_comb begin                                                      // 组合逻辑
    hit_pb=1'b0; hit_eb=1'b0;                                            //   默认都没有
    for (int i=0;i<PSLOTS;i++)                                           //   遍历我方子弹槽
      if (pb_valid[i] && int'(gx)>=int'(pb_x[9*i +: 9])-1 && int'(gx)<int'(pb_x[9*i +: 9])+1 &&  // 有效 且 x 在 ±1 以内
          int'(gy)>=int'(pb_y[9*i +: 9])-4 && int'(gy)<int'(pb_y[9*i +: 9])+4)                   // y 在 ±4 以内 → 2×8 的竖条
        hit_pb=1'b1;                                                     //     命中
    for (int i=0;i<ESLOTS;i++)                                           //   遍历敌弹槽
      if (eb_valid[i] && int'(gx)>=int'(eb_x[9*i +: 9])-1 && int'(gx)<int'(eb_x[9*i +: 9])+1 &&  // 有效 且 x 在 ±1 以内
          int'(gy)>=int'(eb_y[9*i +: 9])-3 && int'(gy)<int'(eb_y[9*i +: 9])+3)                   // y 在 ±3 以内 → 2×6 的短竖条
        hit_eb=1'b1;                                                     //     命中
  end                                                                    //   always_comb 结束

  // ---- 掩体（位图 1 = 存在）----                                          // 第 7 段：画掩体
  logic hit_bunker;                                                      // 内部：这个点是不是掩体
  always_comb begin                                                      // 组合逻辑
    hit_bunker=1'b0;                                                     //   默认不是
    for (int b=0;b<BUNKERS;b++) begin                                    //   遍历 4 个掩体
      if (int'(gx)>=BUNK_X[b] && int'(gx)<BUNK_X[b]+BUNK_W && int'(gy)>=BUNK_Y && int'(gy)<BUNK_Y+BUNK_H) begin  // 点在这个掩体矩形内
        if (bunker_bits[b*BUNK_W*BUNK_H + (int'(gy)-BUNK_Y)*BUNK_W + (int'(gx)-BUNK_X[b])])  // 查位图：这一位是 1 才画
          hit_bunker=1'b1;                                               //     命中
      end                                                                //   矩形判断结束
    end                                                                  //   循环结束
  end                                                                    //   always_comb 结束

  // ---- 神秘飞碟（红色碟形）----                                           // 第 8 段：画 UFO
  logic hit_ufo;                                                         // 内部：这个点是不是 UFO
  always_comb begin                                                      // 组合逻辑
    hit_ufo=1'b0;                                                        //   默认不是
    if (ufo_active) begin                                                //   出现时才画
      automatic int lx = int'(gx) - int'(ufo_x);                         //     局部 x
      automatic int ly = int'(gy) - UFO_Y;                               //     局部 y
      if ((ly>=2 && ly<6 && lx>=1 && lx<19) ||                            //     下半部分：宽 18 的碟身
          (ly>=0 && ly<2 && lx>=6 && lx<14))                              //     上半部分：宽 8 的舱盖
        hit_ufo=1'b1;                                                    //     命中
    end                                                                  //   UFO 判断结束
  end                                                                    //   always_comb 结束

  // ---- HUD：生命(左上第一行)、计分(第二行) ----                           // 第 9 段：状态栏
  logic hud_on;                                                          // 内部：这个点是不是 HUD 文字
  always_comb begin                                                      // 组合逻辑
    hud_on=1'b0;                                                         //   默认不是
    // 生命数字 y=0..7, x=1..8                                            //   生命：8×8 一个数字
    if (int'(gy)>=0 && int'(gy)<=7 && int'(gx)>=1 && int'(gx)<9)          //   点在生命数字的框内
      if (font_row(lives[3:0], gy[2:0])[7-(int'(gx)-1)]) hud_on=1'b1;     //     取该行的 8 位点阵，从第 7 位开始取（bit7 = 最左）
    // 计分 4 位 y=8..15                                                   //   分数：4 个数字并排
    for (int k=0;k<4;k++) begin                                          //   遍历 4 位
      automatic int dx = 1 + 8*k;                                        //     每个数字间隔 8 像素
      if (int'(gy)>=8 && int'(gy)<=15 && int'(gx)>=dx && int'(gx)<dx+8) begin  // 点在这个数字框内
        automatic int div = (k==0)?1000:((k==1)?100:((k==2)?10:1));      //     千位/百位/十位/个位的除数
        automatic int dd = (int'(score)/div)%10;                         //     取出这一位（除法取余）
        if (font_row(dd[3:0], gy[2:0])[7-(int'(gx)-dx)]) hud_on=1'b1;    //     查字模点亮
      end                                                                //   框判断结束
    end                                                                  //   循环结束
  end                                                                    //   always_comb 结束

  // ---- 结束画面：败=灰 GAME OVER，胜=绿 VICTORY! + SCORE ----             // 第 10 段：结束画面
  logic over_on;                                                         // 内部：这个点是不是结束画面
  logic [23:0] over_col;                                                 // 内部：结束画面颜色
  always_comb begin                                                      // 组合逻辑
    over_on = 1'b0;                                                      //   默认不显示
    over_col = 24'h808080;                                               //   默认灰色
    if (stage_show) begin                                                //   在显示波次提示时
      if (stage_blink) begin                                             //     闪烁的"亮"相位
        over_col = 24'hFFFF00;                                           //       黄色文字
        for (int k=0; k<5; k++) begin                                    //       画 "STAGE" 5 个字母
          automatic int cx = int'(gx) - (104 + k*16);                    //         每个字母占 16 像素宽（放大 2 倍）
          automatic int cy = int'(gy) - 112;                             //         文字在 y=112
          if (cx>=0 && cx<16 && cy>=0 && cy<16)                          //         落在这个字母的 16×16 内
            if (alpha_row((k==0)?4'd8:(k==1)?4'd9:(k==2)?4'd0:(k==3)?4'd3:4'd2, cy[3:1])[7-cx[3:1]]) over_on = 1'b1;  // 取字模：cy/2 是行、cx/2 是列（2 倍放大）
        end                                                              //       字母循环结束
        begin                                                            //       画波次数字（1 个）
          automatic int cx = int'(gx) - (104 + 6*16);                    //         第 6 个字符位
          automatic int cy = int'(gy) - 112;                             //         同一行
          if (cx>=0 && cx<16 && cy>=0 && cy<16)                          //         在框内
            if (font_row((stage+1'b1), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;  // 显示"当前波次+1"（因为 stage 从 0 开始）
        end                                                              //       数字块结束
      end else begin                                                     //     闪烁的"灭"相位
        over_on = 1'b1;                                                  //       整屏点亮
        over_col = 24'h000000;                                           //       点亮成黑色（反相闪烁）
      end                                                                //     相位判断结束
    end else if (state == 2'd3) begin                                    //   否则如果是游戏结束状态
      if (win) begin                                                     //     通关
        over_col = 24'h00FF00;                                           //       绿色
        for (int k=0; k<8; k++) begin                                    //       画 "VICTORY!" 8 个字符
          automatic int cx = int'(gx) - (96 + k*16);                     //         从 x=96 开始
          automatic int cy = int'(gy) - 96;                              //         y=96
          if (cx>=0 && cx<16 && cy>=0 && cy<16)                          //         在字符框内
            if (alpha_row(word_code(2'd0,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;  // 查字模
        end                                                              //       循环结束
        for (int k=0; k<7; k++) begin                                    //       画 "SCORE:" 6 个字符（循环 7 次，多的一次是空的）
          automatic int cx = int'(gx) - (80 + k*16);                     //         从 x=80 开始
          automatic int cy = int'(gy) - 112;                             //         下一行 y=112
          if (cx>=0 && cx<16 && cy>=0 && cy<16)                          //         在框内
            if (alpha_row(word_code(2'd1,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;  // 查字模
        end                                                              //       循环结束
        for (int k=0; k<4; k++) begin                                    //       画分数的 4 位数字
          automatic int cx = int'(gx) - (72 + (7+k)*16);                 //         接在 "SCORE:" 后面
          automatic int cy = int'(gy) - 112;                             //         同一行
          if (cx>=0 && cx<16 && cy>=0 && cy<16) begin                    //         在框内
            automatic int div = (k==0)?1000:((k==1)?100:((k==2)?10:1));  //           这一位的除数
            automatic int dd = (int'(score)/div)%10;                     //           取出数字
            if (font_row(dd[3:0], cy[3:1])[7-cx[3:1]]) over_on = 1'b1;   //           查字模
          end                                                            //         框判断结束
        end                                                              //       数字循环结束
      end else begin                                                     //     失败
        for (int k=0; k<9; k++) begin                                    //       画 "GAME OVER" 9 个字符
          automatic int cx = int'(gx) - (88 + k*16);                     //         从 x=88 开始
          automatic int cy = int'(gy) - 112;                             //         y=112
          if (cx>=0 && cx<16 && cy>=0 && cy<16)                          //         在框内
            if (alpha_row(word_code(2'd2,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;  // 查字模
        end                                                              //       循环结束
      end                                                                //   胜负判断结束
    end                                                                  //   stage/state 判断结束
  end                                                                    //   always_comb 结束

  // ---- 优先级输出 ----                                                    // 第 11 段：叠放顺序
  always_comb begin                                                      // 组合逻辑：谁盖谁
    if (over_on)     rgb = over_col;                                     //   结束画面盖一切
    else if (hud_on) rgb = 24'hFFFFFF;                                   //   其次 HUD（白字）
    else if (hit_pb) rgb = 24'hFFFFFF;                                   //   其次我方子弹（白）
    else if (hit_eb) rgb = 24'hFFFFFF;                                   //   敌弹（白）
    else if (hit_player) rgb = 24'h00FF00;                               //   炮台（绿）
    else if (hit_enemy)  rgb = eye ? 24'h000000 : enemy_col;             //   敌机（眼睛黑色）
    else if (hit_bunker) rgb = 24'h00FF00;                               //   掩体（绿）
    else if (hit_ufo)    rgb = 24'hFF0000;                               //   UFO（红）
    else             rgb = 24'h000000;                                   //   都没有 → 黑色背景
  end                                                                    //   always_comb 结束
endmodule                                                               // 模块结束
