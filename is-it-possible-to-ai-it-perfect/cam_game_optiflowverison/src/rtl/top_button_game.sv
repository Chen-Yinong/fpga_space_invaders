// top_button_game.sv — 按键控制版太空侵略者 + HDMI 输出
//   key0(V17)=左移  key1(W17)=右移  key2(AA18)=开始/暂停/继续  key3(AB18)=重开
`timescale 1ns/1ps
module top_button_game (
  input  logic        sys_clk,        // W19 50MHz
  input  logic        sys_rst_n,      // N15
  input  logic        key0,           // V17
  input  logic        key1,           // W17
  input  logic        key2,           // AA18
  input  logic        key3,           // AB18
  output logic        ddc_scl,        // E19
  inout  wire         ddc_sda,        // D19
  output logic        hdmi_out_clk,   // K18
  output logic        hdmi_out_rst_n, // J16
  output logic        hdmi_out_hsync, // K17
  output logic        hdmi_out_vsync, // J17
  output logic        hdmi_out_de,    // K19
  output logic [23:0] hdmi_out_rgb
);
  localparam int PSLOTS=6, ESLOTS=6, FORM_COLS=11, FORM_ROWS=5;
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=12;

  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)
  );

  // 按键消抖（板载按键低有效）
  logic btn_l, btn_r, btn_s, btn_re;
  debounce #(.CNT(250000)) u_l  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key0), .btn_out(btn_l));
  debounce #(.CNT(250000)) u_r  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key1), .btn_out(btn_r));
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));

  // 游戏核心
  logic [8:0]  g_px; logic g_pvis;
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;
  logic [FORM_COLS*FORM_ROWS-1:0] g_ea; logic [8:0] g_ex0, g_ey0;
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] g_bunk;
  logic [15:0] g_score; logic [3:0] g_lives; logic [1:0] g_state;
  logic g_ufo_act; logic [8:0] g_ufo_x;
  logic g_win;
  logic [1:0] g_stage; logic g_stage_show, g_stage_blink;

  game_core #(.TICK_DIV(833333), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (
    .clk_sys(sys_clk), .rst_n(rst_n),
    .btn_left(btn_l), .btn_right(btn_r), .btn_start(btn_s), .btn_restart(btn_re),
    .player_x(g_px), .player_visible(g_pvis),
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),
    .bunker_bits(g_bunk), .score(g_score), .lives(g_lives), .state(g_state),
    .win(g_win), .ufo_active(g_ufo_act), .ufo_x(g_ufo_x),
    .stage(g_stage), .stage_show(g_stage_show), .stage_blink(g_stage_blink)
  );

  // 信箱 CDC：sys_clk -> clk_25m
  logic [11:0] refresh_cnt; logic bus_toggle;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin refresh_cnt<='0; bus_toggle<=1'b0; end
    else if (refresh_cnt==12'd4095) begin refresh_cnt<='0; bus_toggle<=~bus_toggle; end
    else refresh_cnt<=refresh_cnt+1'b1;

  logic t1, t2, t2_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin t1<=1'b0; t2<=1'b0; t2_d<=1'b0; end
    else begin t1<=bus_toggle; t2<=t1; t2_d<=t2; end

  logic [8:0]  p_px; logic p_pvis;
  logic [PSLOTS-1:0]   p_pbv; logic [PSLOTS*9-1:0] p_pbx, p_pby;
  logic [ESLOTS-1:0]   p_ebv; logic [ESLOTS*9-1:0] p_ebx, p_eby;
  logic [FORM_COLS*FORM_ROWS-1:0] p_ea; logic [8:0] p_ex0, p_ey0;
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] p_bunk;
  logic [15:0] p_score; logic [3:0] p_lives; logic [1:0] p_state;
  logic p_ufo_act; logic [8:0] p_ufo_x;
  logic p_win;
  logic [1:0] p_stage; logic p_stage_show, p_stage_blink;

  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin
      p_px<='0; p_pvis<=1'b1; p_pbv<='0; p_pbx<='0; p_pby<='0;
      p_ebv<='0; p_ebx<='0; p_eby<='0; p_ea<='0; p_ex0<='0; p_ey0<='0;
      p_bunk<='1; p_score<='0; p_lives<='0; p_state<='0;
      p_ufo_act<=1'b0; p_ufo_x<='0;
      p_win<=1'b0;
      p_stage<=2'd0; p_stage_show<=1'b0; p_stage_blink<=1'b0;
    end else if (t2 != t2_d) begin
      p_px<=g_px; p_pvis<=g_pvis;
      p_pbv<=g_pbv; p_pbx<=g_pbx; p_pby<=g_pby;
      p_ebv<=g_ebv; p_ebx<=g_ebx; p_eby<=g_eby;
      p_ea<=g_ea; p_ex0<=g_ex0; p_ey0<=g_ey0;
      p_bunk<=g_bunk; p_score<=g_score; p_lives<=g_lives; p_state<=g_state;
      p_ufo_act<=g_ufo_act; p_ufo_x<=g_ufo_x;
      p_win<=g_win;
      p_stage<=g_stage; p_stage_show<=g_stage_show; p_stage_blink<=g_stage_blink;
    end

  // VGA 时序 + 渲染
  logic [11:0] px, py; logic hsync, vsync, va, fs;
  vga_timing u_vga (
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)
  );

  logic [23:0] rgb_c;
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (
    .vid_x(px[9:0]), .vid_y(py[9:0]),
    .player_x(p_px), .player_visible(p_pvis),
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),
    .bunker_bits(p_bunk), .score(p_score), .lives(p_lives), .state(p_state),
    .win(p_win), .ufo_active(p_ufo_act), .ufo_x(p_ufo_x),
    .stage(p_stage), .stage_show(p_stage_show), .stage_blink(p_stage_blink),
    .rgb(rgb_c)
  );

  // 视频输出流水
  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_c; hs_d<=hsync; vs_d<=vsync; va_d<=va; end

  assign hdmi_out_rgb   = rgb_d;
  assign hdmi_out_hsync = hs_d;
  assign hdmi_out_vsync = vs_d;
  assign hdmi_out_de    = va_d;
  assign hdmi_out_clk   = clk_25m;
  assign hdmi_out_rst_n = rst_n;

  // HDMI 芯片配置
  hdmi_i2c u_hdmi_i2c (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),
    .sccb_scl(ddc_scl), .sccb_sda(ddc_sda)
  );
endmodule
