// top_button_game.sv — 按键 -> 消抖 -> game_core -> 信箱跨域 -> 渲染 + VGA时序
`timescale 1ns/1ps
module top_button_game #(
  parameter int TICK_DIV    = 833333,
  parameter int MOVE_PERIOD = 30,
  parameter int DEB_CNT     = 250000,
  parameter int PSLOTS      = 6,
  parameter int ESLOTS      = 3
)(
  input  logic        clk_sys,
  input  logic        clk_pix,
  input  logic        rst_n,
  input  logic        btn_left_raw,
  input  logic        btn_right_raw,
  input  logic        btn_start_raw,
  output logic [23:0] vga_rgb,
  output logic        vga_hsync,
  output logic        vga_vsync,
  output logic        vga_de
);
  // 按键消抖
  logic btn_l, btn_r, btn_s;
  debounce #(.CNT(DEB_CNT)) u_dl (.clk(clk_sys), .rst_n(rst_n), .btn_in(btn_left_raw ), .btn_out(btn_l));
  debounce #(.CNT(DEB_CNT)) u_dr (.clk(clk_sys), .rst_n(rst_n), .btn_in(btn_right_raw), .btn_out(btn_r));
  debounce #(.CNT(DEB_CNT)) u_ds (.clk(clk_sys), .rst_n(rst_n), .btn_in(btn_start_raw), .btn_out(btn_s));

  // 左/右/停 电平（对应手势 gesture_cmd_level）
  logic [1:0] move_cmd;
  assign move_cmd = btn_l ? 2'b01 : btn_r ? 2'b10 : 2'b00;

  // 游戏核心（clk_sys 域）
  logic [8:0] g_px; logic g_pvis;
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;
  logic [49:0] g_ea; logic [8:0] g_ex0, g_ey0;
  logic [15:0] g_score; logic [3:0] g_lives; logic [2:0] g_wave; logic [1:0] g_state;

  game_core #(.TICK_DIV(TICK_DIV), .MOVE_PERIOD(MOVE_PERIOD), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (
    .clk_sys(clk_sys), .rst_n(rst_n), .move_cmd(move_cmd), .btn_start(btn_s),
    .player_x(g_px), .player_visible(g_pvis),
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),
    .score(g_score), .lives(g_lives), .wave(g_wave), .state(g_state)
  );

  // ---- 信箱跨时钟域：clk_sys -> clk_pix ----
  logic [11:0] refresh_cnt; logic bus_toggle;
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin refresh_cnt<='0; bus_toggle<=1'b0; end
    else if (refresh_cnt==12'd4095) begin refresh_cnt<='0; bus_toggle<=~bus_toggle; end
    else refresh_cnt<=refresh_cnt+1'b1;

  logic t1,t2,t2_d;
  always_ff @(posedge clk_pix or negedge rst_n)
    if (!rst_n) begin t1<=1'b0; t2<=1'b0; t2_d<=1'b0; end
    else begin t1<=bus_toggle; t2<=t1; t2_d<=t2; end

  logic [8:0] p_px; logic p_pvis;
  logic [PSLOTS-1:0]   p_pbv; logic [PSLOTS*9-1:0] p_pbx, p_pby;
  logic [ESLOTS-1:0]   p_ebv; logic [ESLOTS*9-1:0] p_ebx, p_eby;
  logic [49:0] p_ea; logic [8:0] p_ex0, p_ey0;
  logic [15:0] p_score; logic [3:0] p_lives; logic [2:0] p_wave; logic [1:0] p_state;

  always_ff @(posedge clk_pix or negedge rst_n)
    if (!rst_n) begin
      p_px<='0; p_pvis<=1'b1; p_pbv<='0; p_pbx<='0; p_pby<='0;
      p_ebv<='0; p_ebx<='0; p_eby<='0; p_ea<='0; p_ex0<='0; p_ey0<='0;
      p_score<='0; p_lives<='0; p_wave<='0; p_state<='0;
    end else if (t2 != t2_d) begin
      p_px<=g_px; p_pvis<=g_pvis;
      p_pbv<=g_pbv; p_pbx<=g_pbx; p_pby<=g_pby;
      p_ebv<=g_ebv; p_ebx<=g_ebx; p_eby<=g_eby;
      p_ea<=g_ea; p_ex0<=g_ex0; p_ey0<=g_ey0;
      p_score<=g_score; p_lives<=g_lives; p_wave<=g_wave; p_state<=g_state;
    end

  // VGA 时序
  logic [11:0] px, py; logic hsync, vsync, va, fs;
  vga_timing u_vga (.clk_pix(clk_pix), .rst_n(rst_n), .x(px), .y(py),
                    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs));

  logic [23:0] rgb_c;
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (
    .vid_x(px[9:0]), .vid_y(py[9:0]),
    .player_x(p_px), .player_visible(p_pvis),
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),
    .score(p_score), .lives(p_lives), .wave(p_wave),
    .rgb(rgb_c)
  );
  // 视频输出加一级流水（缩短渲染组合路径）
  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_pix or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_c; hs_d<=hsync; vs_d<=vsync; va_d<=va; end
  assign vga_rgb   = rgb_d;
  assign vga_hsync = hs_d;
  assign vga_vsync = vs_d;
  assign vga_de    = va_d;
endmodule