// ============================================================================
// top_cam_game.sv —— 逐行注释版（原文件 232 行）★ 顶层：把摄像头、光流、游戏、HDMI 串起来
// 数据流：摄像头 RGB565 → 灰度 → LK 光流 → 手势 FSM → 游戏(左/右) → 取景器 → HDMI
// 两条时钟域：摄像头域 cam1_pclk（光流跑这里）、系统域 50MHz + 像素域 25MHz
// ============================================================================
// top_cam_game.sv — 手势（LK 光流）控制版太空侵略者 + HDMI 游戏画面输出          // 标题
//   手势：向左挥手 = 炮台左移，向右挥手 = 炮台右移，手停 = 不动                  // 玩法说明
//   按键：key2 = 开始/暂停/继续，key3 = 重开                                      // 按键说明
`timescale 1ns/1ps                                                      // 仿真时间精度 1ns/1ps
module top_cam_game (                                                   // 顶层模块声明
  input  logic        sys_clk,        // W19 50MHz                     // 输入：50MHz 主时钟
  input  logic        sys_rst_n,      // N15                           // 输入：复位（低有效）
  // OV7725 摄像头                                                       // —— 摄像头接口 ——
  input  logic        cam1_pclk,      // AA21                          // 输入：摄像头像素时钟（约 25MHz）
  input  logic        cam1_vsync,     // T18                           // 输入：场同步
  input  logic        cam1_href,      // T21                           // 输入：行同步
  input  logic [7:0]  cam1_data,      // N14..U21                      // 输入：8 位并行数据
  output logic        cam_rst_n,      // P16                           // 输出：摄像头复位
  output logic        cam_pwdn,       // R17                           // 输出：摄像头掉电控制
  output logic        sccb1_scl,      // R14                           // 输出：SCCB 时钟（类 I2C）
  inout  wire         sccb1_sda,      // P14                           // 双向：SCCB 数据
  // 按键（开始/重开，保留物理按键）                                      // —— 按键 ——
  input  logic        key2,           // AA18                          // 输入：开始/暂停键
  input  logic        key3,           // AB18                          // 输入：重开键
  // HDMI                                                                // —— HDMI 输出 ——
  output logic        ddc_scl,        // E19                           // 输出：DDC(I2C) 时钟，配置 HDMI 芯片
  inout  wire         ddc_sda,        // D19                           // 双向：DDC(I2C) 数据
  output logic        hdmi_out_clk,   // K18                           // 输出：HDMI 像素时钟 25MHz
  output logic        hdmi_out_rst_n, // J16                           // 输出：HDMI 芯片复位
  output logic        hdmi_out_hsync, // K17                           // 输出：行同步
  output logic        hdmi_out_vsync, // J17                           // 输出：场同步
  output logic        hdmi_out_de,    // K19                           // 输出：数据有效
  output logic [23:0] hdmi_out_rgb,                                   // 输出：24 位 RGB888
  // 手势指示 LED                                                        // —— LED ——
  output logic        led_stop,       // M21                           // 输出：停止指示（本工程不点亮）
  output logic        led_left,       // L21                           // 输出：左移指示（本工程不点亮）
  output logic        led_right       // K21                           // 输出：右移指示（本工程不点亮）
);                                                                      // 端口结束
  localparam int PSLOTS=6, ESLOTS=6, FORM_COLS=11, FORM_ROWS=5;         // 常量：我方 6 发子弹槽、敌方 6 发敌弹槽、敌机编队 11 列×5 行（共 55 格）
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=12;                        // 常量：4 个掩体，每个 24×12 像素

  // ---- 时钟与复位 ----
  logic clk_25m, locked, rst_n;                                          // 内部：25MHz 像素时钟、PLL 锁定、内部复位
  assign rst_n = sys_rst_n & locked;                                     // 组合：外部复位有效 且 PLL 已锁定，系统才退出复位
  hdmi_pll u_pll (                                                       // 例化 PLL（IP）
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)  //   50MHz 进 → 25MHz 出；reset 高有效所以取反
  );                                                                     //   例化结束
  assign cam_rst_n = 1'b1;                                               // 组合：摄像头复位脚常高（不复位）
  assign cam_pwdn  = 1'b0;                                               // 组合：掉电脚常低（正常工作，不是掉电）

  // ---- 摄像头采集 ----
  logic cam_cfg_done, cam_wr_en;                                         // 内部：配置完成标志、像素写使能
  logic [15:0] cam_wr_data;                                              // 内部：摄像头输出的 RGB565 像素
  ov7725_top u_cam (                                                     // 例化摄像头驱动（board_cam 目录）
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),  //   时钟复位 + 初始化完成后开始出图
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href),                    //   接摄像头原生同步信号
    .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),                  //   场同步 + 8 位数据
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),//   输出配置完成 + SCCB 总线
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)              //   输出：像素有效 + RGB565 数据
  );                                                                     //   例化结束

  // ---- 灰度 + LK 光流 ----
  logic [7:0] cur_gray;                                                  // 内部：当前像素的灰度值
  rgb2gray u_gray (.pixel(cam_wr_data), .gray(cur_gray));                // 例化 RGB565→灰度（用整数近似公式）

  logic flow_valid;                                                      // 内部：一个块的求解结果有效
  logic signed [31:0] flow_u, flow_v;                                    // 内部：该块的水平/垂直位移（Q16）
  logic [31:0] flow_energy;                                              // 内部：该块纹理能量（A+C）
  logic [4:0] flow_bx;                                                   // 内部：块列号
  logic [3:0] flow_by;                                                   // 内部：块行号
  lk_flow u_flow (                                                       // 例化 LK 光流核心
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en),               //   注意：用摄像头时钟跑光流
    .cur_gray(cur_gray), .href(cam1_href), .vsync(cam1_vsync),           //   灰度 + 原生同步信号
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),           //   输出有效 + u/v
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by)      //   输出能量 + 块坐标
  );                                                                     //   例化结束

  // ---- VGA 时序 ----
  logic [11:0] px, py;                                                   // 内部：当前扫描像素的 x/y 坐标
  logic hsync, vsync, va, fs;                                            // 内部：行同步/场同步/数据有效/帧首标志
  vga_timing u_vga (                                                     // 例化 640×480@60Hz 时序发生器
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),                    //   25MHz 像素时钟 → 坐标
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)    //   输出同步信号与有效区
  );                                                                     //   例化结束

  // ---- 手势 FSM ----
  logic gest_left, gest_right;                                           // 内部：左挥手、右挥手（摄像头时钟域产出）
  // 右上角画中画：160x120 = 20x15 块 x 8 像素，显示光流矢量场                  // 说明：PIP = picture in picture
  localparam int PIP_X0 = 472, PIP_Y0 = 8, PIP_W = 160, PIP_H = 120;     // 常量：画中画左上角 (472,8)，尺寸 160×120
  wire in_pip = (px >= PIP_X0) && (px < PIP_X0 + PIP_W) && (py >= PIP_Y0) && (py < PIP_Y0 + PIP_H);  // 组合：当前扫描点在不在画中画区域
  wire [7:0] pip_lx = px - PIP_X0;                                       // 组合：画中画内的局部 x（0..159）
  wire [7:0] pip_ly = py - PIP_Y0;                                       // 组合：画中画内的局部 y（0..119）
  wire [11:0] fsm_px = in_pip ? {4'd0, pip_lx} : 12'd0;                  // 组合：不在 PIP 内就喂 0（FSM 只关心 PIP 区）
  wire [11:0] fsm_py = in_pip ? {4'd0, pip_ly} : 12'd0;                  // 组合：同上，y 方向
  logic [1:0] tag_out;                                                   // 内部：当前显示点所属块的标签（0 静止/1 左/2 右）
  flow_fsm #(.TAG_SHIFT(3)) u_fsm (                                      // 例化手势判决 FSM（TAG_SHIFT=3 表示每块 8×8 像素）
    .pclk(cam1_pclk), .rst_n(rst_n),                                     //   摄像头时钟域
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),           //   输入光流结果
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by),     //   输入块坐标与能量
    .vsync(cam1_vsync),                                                  //   场同步用于清场
    .clk_disp(clk_25m), .px(fsm_px), .py(fsm_py), .tag_out(tag_out),     //   显示域：给坐标，返回标签
    .led_stop(), .led_left(gest_left), .led_right(gest_right)            //   输出手势（led_stop 悬空不用）
  );                                                                     //   例化结束
  // LED 不点亮：手势状态只用于游戏控制                                       // 说明：板上 LED 太刺眼，全部关掉
  assign led_stop  = 1'b0;                                               // 组合：停止灯恒灭
  assign led_left  = 1'b0;                                               // 组合：左灯恒灭
  assign led_right = 1'b0;                                               // 组合：右灯恒灭

  // ---- 手势状态跨时钟域同步（pclk -> sys_clk，2FF）----                   // 第 1 段：CDC
  // 摄像头为镜像输出：画面中的"左"对应现实中的"右"，左右对调后接游戏          // 说明：镜子效应
  logic gl_s1, gl_s2, gr_s1, gr_s2;                                      // 内部：两级同步寄存器（左右各一对）
  always_ff @(posedge sys_clk or negedge rst_n)                           // 时序逻辑：50MHz 域采样手势
    if (!rst_n) begin gl_s1<=1'b0; gl_s2<=1'b0; gr_s1<=1'b0; gr_s2<=1'b0; end  //   复位清零
    else begin                                                           //   正常
      gl_s1<=gest_right; gl_s2<=gl_s1;   // 游戏左 = 画面右               //     交叉接线：画面右挥手 → 游戏左
      gr_s1<=gest_left;  gr_s2<=gr_s1;   // 游戏右 = 画面左               //     交叉接线：画面左挥手 → 游戏右
    end                                                                  //   if/else 结束

  // ---- 按键消抖（key2/key3，低有效）----                                  // 第 2 段：按键
  logic btn_s, btn_re;                                                   // 内部：消抖后的开始键、重开键
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));   // 例化消抖：50MHz 下 25 万拍 ≈ 5ms；按键低有效所以要取反
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));  // 同上，重开键

  // ---- 游戏核心（左/右 = 手势，开始/重开 = 按键）----                      // 第 3 段：游戏
  logic [8:0]  g_px; logic g_pvis;                                       // 内部：炮台 x 坐标、炮台是否可见
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;         // 内部：我方子弹有效位 + 每发的 x/y（每发 9 位，打包成总线）
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;         // 内部：敌弹有效位 + x/y
  logic [FORM_COLS*FORM_ROWS-1:0] g_ea; logic [8:0] g_ex0, g_ey0;        // 内部：55 个敌机的存活位图 + 编队左上角坐标
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] g_bunk;                              // 内部：4 个掩体的像素位图（24×12×4 位）
  logic [15:0] g_score; logic [3:0] g_lives; logic [1:0] g_state;        // 内部：分数、生命、状态（0 待机/1 开局/2 游戏中/3 结束）
  logic g_ufo_act; logic [8:0] g_ufo_x;                                  // 内部：UFO 是否出现 + x 坐标
  logic g_win;                                                           // 内部：通关标志
  logic [1:0] g_stage; logic g_stage_show, g_stage_blink;                // 内部：波次、波次提示是否显示、是否闪烁

  game_core #(.TICK_DIV(833333), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (  // 例化游戏核心：TICK_DIV=833333，50MHz/833333 ≈ 60Hz 游戏节拍
    .clk_sys(sys_clk), .rst_n(rst_n),                                    //   50MHz 域
    .btn_left(gl_s2), .btn_right(gr_s2), .btn_start(btn_s), .btn_restart(btn_re),  //   左右来自手势，开始/重开来自按键
    .player_x(g_px), .player_visible(g_pvis),                            //   输出：炮台位置
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),                        //   输出：我方子弹
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),                        //   输出：敌方子弹
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),              //   输出：敌机存活位图 + 编队位置
    .bunker_bits(g_bunk), .score(g_score), .lives(g_lives), .state(g_state),  // 输出：掩体、分数、生命、状态
    .win(g_win), .ufo_active(g_ufo_act), .ufo_x(g_ufo_x),                //   输出：通关、UFO
    .stage(g_stage), .stage_show(g_stage_show), .stage_blink(g_stage_blink)   // 输出：波次提示
  );                                                                     //   例化结束

  // ---- 信箱 CDC：sys_clk -> clk_25m ----                                 // 第 4 段：把 50MHz 域的游戏状态搬到 25MHz 显示域
  logic [11:0] refresh_cnt; logic bus_toggle;                            // 内部：刷新计数器、刷新标志（每 4096 拍翻一次）
  always_ff @(posedge sys_clk or negedge rst_n)                           // 时序逻辑：产生刷新脉冲
    if (!rst_n) begin refresh_cnt<='0; bus_toggle<=1'b0; end             //   复位清零
    else if (refresh_cnt==12'd4095) begin refresh_cnt<='0; bus_toggle<=~bus_toggle; end  // 数满 4096 → 清零并翻转标志
    else refresh_cnt<=refresh_cnt+1'b1;                                  //   否则继续计数

  logic t1, t2, t2_d;                                                    // 内部：显示域里的两级同步 + 打一拍
  always_ff @(posedge clk_25m or negedge rst_n)                          // 时序逻辑：25MHz 域同步刷新标志
    if (!rst_n) begin t1<=1'b0; t2<=1'b0; t2_d<=1'b0; end                //   复位清零
    else begin t1<=bus_toggle; t2<=t1; t2_d<=t2; end                     //   t1 一级同步、t2 二级同步、t2_d 再打一拍用于检测变化

  logic [8:0]  p_px; logic p_pvis;                                       // 内部：显示域锁存的炮台位置（p_ 前缀 = 显示域副本）
  logic [PSLOTS-1:0]   p_pbv; logic [PSLOTS*9-1:0] p_pbx, p_pby;         // 内部：显示域的子弹数据
  logic [ESLOTS-1:0]   p_ebv; logic [ESLOTS*9-1:0] p_ebx, p_eby;         // 内部：显示域的敌弹数据
  logic [FORM_COLS*FORM_ROWS-1:0] p_ea; logic [8:0] p_ex0, p_ey0;        // 内部：显示域的敌机位图与编队坐标
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] p_bunk;                              // 内部：显示域的掩体位图
  logic [15:0] p_score; logic [3:0] p_lives; logic [1:0] p_state;        // 内部：显示域的分数/生命/状态
  logic p_ufo_act; logic [8:0] p_ufo_x;                                  // 内部：显示域的 UFO
  logic p_win;                                                           // 内部：显示域的通关标志
  logic [1:0] p_stage; logic p_stage_show, p_stage_blink;                // 内部：显示域的波次

  always_ff @(posedge clk_25m or negedge rst_n)                           // 时序逻辑：一次性把整包游戏状态搬过来
    if (!rst_n) begin                                                    //   复位
      p_px<='0; p_pvis<=1'b1; p_pbv<='0; p_pbx<='0; p_pby<='0;           //     炮台/子弹清零（炮台默认可见）
      p_ebv<='0; p_ebx<='0; p_eby<='0; p_ea<='0; p_ex0<='0; p_ey0<='0;   //     敌弹/敌机清零
      p_bunk<='1; p_score<='0; p_lives<='0; p_state<='0;                 //     掩体全满、分数/生命/状态清零
      p_ufo_act<=1'b0; p_ufo_x<='0;                                      //     UFO 隐藏
      p_win<=1'b0;                                                       //     未通关
      p_stage<=2'd0; p_stage_show<=1'b0; p_stage_blink<=1'b0;           //     波次清零、提示隐藏
    end else if (t2 != t2_d) begin                                       //   检测到刷新标志变化 → 搬一次
      p_px<=g_px; p_pvis<=g_pvis;                                        //     炮台
      p_pbv<=g_pbv; p_pbx<=g_pbx; p_pby<=g_pby;                          //     我方子弹
      p_ebv<=g_ebv; p_ebx<=g_ebx; p_eby<=g_eby;                          //     敌方子弹
      p_ea<=g_ea; p_ex0<=g_ex0; p_ey0<=g_ey0;                            //     敌机
      p_bunk<=g_bunk; p_score<=g_score; p_lives<=g_lives; p_state<=g_state;  // 掩体/分数/生命/状态
      p_ufo_act<=g_ufo_act; p_ufo_x<=g_ufo_x;                            //     UFO
      p_win<=g_win;                                                      //     通关
      p_stage<=g_stage; p_stage_show<=g_stage_show; p_stage_blink<=g_stage_blink;  // 波次提示
    end                                                                  //   if 结束

  // ---- 渲染 + 输出 ----                                                   // 第 5 段：画像素
  logic [23:0] rgb_c;                                                    // 内部：游戏画面颜色
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (            // 例化精灵渲染器（组合逻辑，输入坐标输出颜色）
    .vid_x(px[9:0]), .vid_y(py[9:0]),                                    //   当前扫描坐标（只取低 10 位 = 0..639/0..479）
    .player_x(p_px), .player_visible(p_pvis),                            //   炮台
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),                        //   我方子弹
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),                        //   敌方子弹
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),              //   敌机
    .bunker_bits(p_bunk), .score(p_score), .lives(p_lives), .state(p_state),  // 掩体/HUD/状态
    .win(p_win), .ufo_active(p_ufo_act), .ufo_x(p_ufo_x),                //   通关/UFO
    .stage(p_stage), .stage_show(p_stage_show), .stage_blink(p_stage_blink),  // 波次提示
    .rgb(rgb_c)                                                          //   输出颜色
  );                                                                     //   例化结束

  // ---- 画中画矢量场（左=红，右=绿，静止=深灰，带灰白边框）----              // 第 6 段：调试用的光流可视化
  logic [23:0] pip_rgb;                                                  // 内部：画中画内部颜色
  always_comb begin                                                      // 组合逻辑：按标签选颜色
    case (tag_out)                                                       //   看这个块被判成什么
      2'd1:    pip_rgb = 24'hFF3030;                                     //     1 = 向左 → 红色
      2'd2:    pip_rgb = 24'h30FF30;                                     //     2 = 向右 → 绿色
      default: pip_rgb = 24'h181818;                                     //     0 = 静止/不可信 → 深灰
    endcase                                                              //   case 结束
  end                                                                    //   always_comb 结束
  wire pip_border = in_pip && ((pip_lx < 8'd2) || (pip_lx >= PIP_W - 2) ||  // 组合：画中画的边框条件（距边缘 2 像素内）
                               (pip_ly < 8'd2) || (pip_ly >= PIP_H - 2));  //   上下左右四条边
  logic [23:0] rgb_src;                                                  // 内部：最终送显示的颜色
  always_comb begin                                                      // 组合逻辑：画面三选一
    if (pip_border)       rgb_src = 24'hC0C0C0;                          //   在边框上 → 灰白
    else if (in_pip)      rgb_src = pip_rgb;                             //   在画中画里 → 矢量场颜色
    else                  rgb_src = rgb_c;                               //   其他地方 → 游戏画面
  end                                                                    //   always_comb 结束

  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;                            // 内部：输出寄存器（打一拍改善时序）
  always_ff @(posedge clk_25m or negedge rst_n)                           // 时序逻辑：输出对齐
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end //   复位清零
    else begin rgb_d<=rgb_src; hs_d<=hsync; vs_d<=vsync; va_d<=va; end   //   颜色和三个同步信号一起打一拍

  assign hdmi_out_rgb   = rgb_d;                                         // 组合：颜色送 HDMI
  assign hdmi_out_hsync = hs_d;                                          // 组合：行同步送 HDMI
  assign hdmi_out_vsync = vs_d;                                          // 组合：场同步送 HDMI
  assign hdmi_out_de    = va_d;                                          // 组合：数据有效送 HDMI
  assign hdmi_out_clk   = clk_25m;                                       // 组合：25MHz 像素时钟送 HDMI
  assign hdmi_out_rst_n = rst_n;                                         // 组合：复位送 HDMI 芯片

  // ---- HDMI 芯片配置 ----                                                 // 第 7 段：上电后通过 I2C 写 ADV7511 寄存器
  hdmi_i2c u_hdmi_i2c (                                                  // 例化 HDMI 配置器（board_hdmi 目录）
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),                   //   时钟复位；完成标志不用（悬空）
    .sccb_scl(ddc_scl), .sccb_sda(ddc_sda)                               //   接 DDC 的 I2C 总线
  );                                                                     //   例化结束
endmodule                                                               // 模块结束
