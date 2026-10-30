// ============================================================================
// top_button_game.sv —— 逐行注释版（原文件 138 行）★ 纯按键版顶层（没有摄像头）
// 和 top_cam_game.sv 的区别：没有 OV7725、没有光流、没有手势 FSM，
// 左右移动直接来自 key0/key1。用来单独验证游戏 + HDMI 链路是否正常。
// ============================================================================
// top_button_game.sv — 按键控制版太空侵略者 + HDMI 输出                       // 标题
//   key0(V17)=左移  key1(W17)=右移  key2(AA18)=开始/暂停/继续  key3(AB18)=重开  // 按键定义
`timescale 1ns/1ps                                                      // 仿真时间精度
module top_button_game (                                                // 顶层模块声明
  input  logic        sys_clk,        // W19 50MHz                     // 输入：50MHz 主时钟
  input  logic        sys_rst_n,      // N15                           // 输入：复位（低有效）
  input  logic        key0,           // V17                           // 输入：左移键
  input  logic        key1,           // W17                           // 输入：右移键
  input  logic        key2,           // AA18                          // 输入：开始/暂停/继续
  input  logic        key3,           // AB18                          // 输入：重开
  output logic        ddc_scl,        // E19                           // 输出：HDMI 芯片 I2C 时钟
  inout  wire         ddc_sda,        // D19                           // 双向：HDMI 芯片 I2C 数据
  output logic        hdmi_out_clk,   // K18                           // 输出：HDMI 像素时钟 25MHz
  output logic        hdmi_out_rst_n, // J16                           // 输出：HDMI 芯片复位
  output logic        hdmi_out_hsync, // K17                           // 输出：行同步
  output logic        hdmi_out_vsync, // J17                           // 输出：场同步
  output logic        hdmi_out_de,    // K19                           // 输出：数据有效
  output logic [23:0] hdmi_out_rgb    //                               // 输出：24 位 RGB888
);                                                                      // 端口结束
  localparam int PSLOTS=6, ESLOTS=6, FORM_COLS=11, FORM_ROWS=5;         // 常量：我方 6 发子弹、敌方 6 发敌弹、编队 11 列 5 行
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=12;                        // 常量：4 个掩体，每个 24×12

  logic clk_25m, locked, rst_n;                                          // 内部：25MHz 像素时钟、PLL 锁定、内部复位
  assign rst_n = sys_rst_n & locked;                                     // 组合：外部复位与 PLL 锁定都满足才出复位
  hdmi_pll u_pll (                                                       // 例化 PLL：50MHz → 25MHz
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)  //   reset 高有效所以取反
  );                                                                     //   例化结束

  // 按键消抖（板载按键低有效）                                             // 第 1 段：按键
  logic btn_l, btn_r, btn_s, btn_re;                                     // 内部：消抖后的左/右/开始/重开
  debounce #(.CNT(250000)) u_l  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key0), .btn_out(btn_l));   // 左移键：25 万拍 ≈ 5ms（50MHz 下）
  debounce #(.CNT(250000)) u_r  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key1), .btn_out(btn_r));   // 右移键
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));   // 开始键
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));  // 重开键

  // 游戏核心                                                              // 第 2 段：游戏
  logic [8:0]  g_px; logic g_pvis;                                       // 内部：炮台 x、可见性
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;         // 内部：我方子弹有效位 + x/y
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;         // 内部：敌弹
  logic [FORM_COLS*FORM_ROWS-1:0] g_ea; logic [8:0] g_ex0, g_ey0;        // 内部：敌机存活位图 + 编队左上角
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] g_bunk;                              // 内部：掩体位图
  logic [15:0] g_score; logic [3:0] g_lives; logic [1:0] g_state;        // 内部：分数/生命/状态
  logic g_ufo_act; logic [8:0] g_ufo_x;                                  // 内部：UFO
  logic g_win;                                                           // 内部：通关
  logic [1:0] g_stage; logic g_stage_show, g_stage_blink;                // 内部：波次与提示

  game_core #(.TICK_DIV(833333), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (  // 例化游戏核心：833333 → 50MHz/833333 ≈ 60Hz 游戏节拍
    .clk_sys(sys_clk), .rst_n(rst_n),                                    //   50MHz 域
    .btn_left(btn_l), .btn_right(btn_r), .btn_start(btn_s), .btn_restart(btn_re),  //   四个按键直接驱动
    .player_x(g_px), .player_visible(g_pvis),                            //   炮台
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),                        //   我方子弹
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),                        //   敌方子弹
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),              //   敌机
    .bunker_bits(g_bunk), .score(g_score), .lives(g_lives), .state(g_state),  // 掩体/HUD/状态
    .win(g_win), .ufo_active(g_ufo_act), .ufo_x(g_ufo_x),                //   通关/UFO
    .stage(g_stage), .stage_show(g_stage_show), .stage_blink(g_stage_blink)   // 波次提示
  );                                                                     //   例化结束

  // 信箱 CDC：sys_clk -> clk_25m                                          // 第 3 段：跨时钟域
  logic [11:0] refresh_cnt; logic bus_toggle;                            // 内部：4096 拍翻转一次的刷新标志
  always_ff @(posedge sys_clk or negedge rst_n)                          // 时序逻辑：产生刷新标志（50MHz 域）
    if (!rst_n) begin refresh_cnt<='0; bus_toggle<=1'b0; end             //   复位清零
    else if (refresh_cnt==12'd4095) begin refresh_cnt<='0; bus_toggle<=~bus_toggle; end  // 数满 4096 → 清零并翻转
    else refresh_cnt<=refresh_cnt+1'b1;                                  //   继续计数

  logic t1, t2, t2_d;                                                    // 内部：显示域的同步链
  always_ff @(posedge clk_25m or negedge rst_n)                          // 时序逻辑：25MHz 域同步刷新标志
    if (!rst_n) begin t1<=1'b0; t2<=1'b0; t2_d<=1'b0; end                //   复位清零
    else begin t1<=bus_toggle; t2<=t1; t2_d<=t2; end                     //   两级同步 + 再来一拍用于检测变化

  logic [8:0]  p_px; logic p_pvis;                                       // 内部：显示域副本（p_ = pixel 域）
  logic [PSLOTS-1:0]   p_pbv; logic [PSLOTS*9-1:0] p_pbx, p_pby;         // 内部：显示域的我方子弹
  logic [ESLOTS-1:0]   p_ebv; logic [ESLOTS*9-1:0] p_ebx, p_eby;         // 内部：显示域的敌弹
  logic [FORM_COLS*FORM_ROWS-1:0] p_ea; logic [8:0] p_ex0, p_ey0;        // 内部：显示域的敌机
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] p_bunk;                              // 内部：显示域的掩体
  logic [15:0] p_score; logic [3:0] p_lives; logic [1:0] p_state;        // 内部：显示域的分数/生命/状态
  logic p_ufo_act; logic [8:0] p_ufo_x;                                  // 内部：显示域的 UFO
  logic p_win;                                                           // 内部：显示域的通关
  logic [1:0] p_stage; logic p_stage_show, p_stage_blink;                // 内部：显示域的波次

  always_ff @(posedge clk_25m or negedge rst_n)                          // 时序逻辑：整包搬运游戏状态
    if (!rst_n) begin                                                    //   复位
      p_px<='0; p_pvis<=1'b1; p_pbv<='0; p_pbx<='0; p_pby<='0;           //     炮台/子弹
      p_ebv<='0; p_ebx<='0; p_eby<='0; p_ea<='0; p_ex0<='0; p_ey0<='0;   //     敌弹/敌机
      p_bunk<='1; p_score<='0; p_lives<='0; p_state<='0;                 //     掩体满/分数/生命/状态
      p_ufo_act<=1'b0; p_ufo_x<='0;                                      //     UFO 隐藏
      p_win<=1'b0;                                                       //     未通关
      p_stage<=2'd0; p_stage_show<=1'b0; p_stage_blink<=1'b0;           //     波次清零
    end else if (t2 != t2_d) begin                                       //   刷新标志变化时搬一次
      p_px<=g_px; p_pvis<=g_pvis;                                        //     炮台
      p_pbv<=g_pbv; p_pbx<=g_pbx; p_pby<=g_pby;                          //     我方子弹
      p_ebv<=g_ebv; p_ebx<=g_ebx; p_eby<=g_eby;                          //     敌方子弹
      p_ea<=g_ea; p_ex0<=g_ex0; p_ey0<=g_ey0;                            //     敌机
      p_bunk<=g_bunk; p_score<=g_score; p_lives<=g_lives; p_state<=g_state;  // 掩体/分数/生命/状态
      p_ufo_act<=g_ufo_act; p_ufo_x<=g_ufo_x;                            //     UFO
      p_win<=g_win;                                                      //     通关
      p_stage<=g_stage; p_stage_show<=g_stage_show; p_stage_blink<=g_stage_blink;  // 波次
    end                                                                  //   if 结束

  // VGA 时序 + 渲染                                                       // 第 4 段：画图
  logic [11:0] px, py; logic hsync, vsync, va, fs;                       // 内部：坐标与同步信号
  vga_timing u_vga (                                                     // 例化 VGA 时序
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),                    //   25MHz → 坐标
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)    //   同步信号（fs 没用上）
  );                                                                     //   例化结束

  logic [23:0] rgb_c;                                                    // 内部：游戏画面颜色
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (            // 例化渲染器
    .vid_x(px[9:0]), .vid_y(py[9:0]),                                    //   扫描坐标（低 10 位）
    .player_x(p_px), .player_visible(p_pvis),                            //   炮台
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),                        //   我方子弹
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),                        //   敌方子弹
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),              //   敌机
    .bunker_bits(p_bunk), .score(p_score), .lives(p_lives), .state(p_state),  // 掩体/HUD/状态
    .win(p_win), .ufo_active(p_ufo_act), .ufo_x(p_ufo_x),                //   通关/UFO
    .stage(p_stage), .stage_show(p_stage_show), .stage_blink(p_stage_blink),  // 波次
    .rgb(rgb_c)                                                          //   输出
  );                                                                     //   例化结束

  // 视频输出流水                                                          // 第 5 段：输出
  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;                            // 内部：输出寄存器
  always_ff @(posedge clk_25m or negedge rst_n)                          // 时序逻辑：打一拍
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end //   复位清零
    else begin rgb_d<=rgb_c; hs_d<=hsync; vs_d<=vsync; va_d<=va; end     //   颜色与同步一起延迟一拍

  assign hdmi_out_rgb   = rgb_d;                                         // 组合：颜色
  assign hdmi_out_hsync = hs_d;                                          // 组合：行同步
  assign hdmi_out_vsync = vs_d;                                          // 组合：场同步
  assign hdmi_out_de    = va_d;                                          // 组合：数据有效
  assign hdmi_out_clk   = clk_25m;                                       // 组合：像素时钟
  assign hdmi_out_rst_n = rst_n;                                         // 组合：复位

  // HDMI 芯片配置                                                         // 第 6 段：配置 ADV7511
  hdmi_i2c u_hdmi_i2c (                                                  // 例化 HDMI 配置器
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),                   //   时钟复位，完成标志不用
    .sccb_scl(ddc_scl), .sccb_sda(ddc_sda)                               //   I2C 总线
  );                                                                     //   例化结束
endmodule                                                               // 模块结束
