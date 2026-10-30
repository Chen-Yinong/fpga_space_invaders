// top_cam_game.sv — 手势（LK 光流）控制版太空侵略者 + HDMI 游戏画面输出
//   手势：向左挥手 = 炮台左移，向右挥手 = 炮台右移，手停 = 不动
//   按键：key2 = 开始/暂停/继续，key3 = 重开
`timescale 1ns/1ps
module top_cam_game (
  input  logic        sys_clk,        // W19 50MHz
  input  logic        sys_rst_n,      // N15
  // OV7725 摄像头
  input  logic        cam1_pclk,      // AA21
  input  logic        cam1_vsync,     // T18
  input  logic        cam1_href,      // T21
  input  logic [7:0]  cam1_data,      // N14..U21
  output logic        cam_rst_n,      // P16
  output logic        cam_pwdn,       // R17
  output logic        sccb1_scl,      // R14
  inout  wire         sccb1_sda,      // P14
  // 按键（开始/重开，保留物理按键）
  input  logic        key2,           // AA18
  input  logic        key3,           // AB18
  // HDMI
  output logic        ddc_scl,        // E19
  inout  wire         ddc_sda,        // D19
  output logic        hdmi_out_clk,   // K18
  output logic        hdmi_out_rst_n, // J16
  output logic        hdmi_out_hsync, // K17
  output logic        hdmi_out_vsync, // J17
  output logic        hdmi_out_de,    // K19
  output logic [23:0] hdmi_out_rgb,
  // 手势指示 LED
  output logic        led_stop,       // M21
  output logic        led_left,       // L21
  output logic        led_right       // K21
);
  localparam int PSLOTS=6, ESLOTS=6, FORM_COLS=11, FORM_ROWS=5;
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=12;

  // ---- 时钟与复位 ----
  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)
  );
  assign cam_rst_n = 1'b1;
  assign cam_pwdn  = 1'b0;

  // ---- 摄像头采集 ----
  logic cam_cfg_done, cam_wr_en;
  logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href),
    .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  // ---- 灰度 + LK 光流 ----
  logic [7:0] cur_gray;
  rgb2gray u_gray (.pixel(cam_wr_data), .gray(cur_gray));

  logic flow_valid;
  logic signed [31:0] flow_u, flow_v;
  logic [31:0] flow_energy;
  logic [4:0] flow_bx;
  logic [3:0] flow_by;
  lk_flow u_flow (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en),
    .cur_gray(cur_gray), .href(cam1_href), .vsync(cam1_vsync),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by)
  );

  // ---- VGA 时序 ----
  logic [11:0] px, py;
  logic hsync, vsync, va, fs;
  vga_timing u_vga (
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)
  );

  // ---- 手势 FSM ----
  logic gest_left, gest_right;
  // 右上角画中画：160x120 = 20x15 块 x 8 像素，显示光流矢量场
  localparam int PIP_X0 = 472, PIP_Y0 = 8, PIP_W = 160, PIP_H = 120;
  wire in_pip = (px >= PIP_X0) && (px < PIP_X0 + PIP_W) && (py >= PIP_Y0) && (py < PIP_Y0 + PIP_H);
  wire [7:0] pip_lx = px - PIP_X0;
  wire [7:0] pip_ly = py - PIP_Y0;
  wire [11:0] fsm_px = in_pip ? {4'd0, pip_lx} : 12'd0;
  wire [11:0] fsm_py = in_pip ? {4'd0, pip_ly} : 12'd0;
  logic [1:0] tag_out;
  flow_fsm #(.TAG_SHIFT(3)) u_fsm (
    .pclk(cam1_pclk), .rst_n(rst_n),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by),
    .vsync(cam1_vsync),
    .clk_disp(clk_25m), .px(fsm_px), .py(fsm_py), .tag_out(tag_out),
    .led_stop(), .led_left(gest_left), .led_right(gest_right)
  );
  // LED 不点亮：手势状态只用于游戏控制
  assign led_stop  = 1'b0;
  assign led_left  = 1'b0;
  assign led_right = 1'b0;

  // ---- 手势状态跨时钟域同步（pclk -> sys_clk，2FF）----
  // 摄像头为镜像输出：画面中的"左"对应现实中的"右"，左右对调后接游戏
  logic gl_s1, gl_s2, gr_s1, gr_s2;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin gl_s1<=1'b0; gl_s2<=1'b0; gr_s1<=1'b0; gr_s2<=1'b0; end
    else begin
      gl_s1<=gest_right; gl_s2<=gl_s1;   // 游戏左 = 画面右
      gr_s1<=gest_left;  gr_s2<=gr_s1;   // 游戏右 = 画面左
    end

  // ---- 按键消抖（key2/key3，低有效）----
  logic btn_s, btn_re;
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));

  // ---- 游戏核心（左/右 = 手势，开始/重开 = 按键）----
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
    .btn_left(gl_s2), .btn_right(gr_s2), .btn_start(btn_s), .btn_restart(btn_re),
    .player_x(g_px), .player_visible(g_pvis),
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),
    .bunker_bits(g_bunk), .score(g_score), .lives(g_lives), .state(g_state),
    .win(g_win), .ufo_active(g_ufo_act), .ufo_x(g_ufo_x),
    .stage(g_stage), .stage_show(g_stage_show), .stage_blink(g_stage_blink)
  );

  // ---- 信箱 CDC：sys_clk -> clk_25m ----
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

  // ---- 渲染 + 输出 ----
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

  // ---- 画中画矢量场（左=红，右=绿，静止=深灰，带灰白边框）----
  logic [23:0] pip_rgb;
  always_comb begin
    case (tag_out)
      2'd1:    pip_rgb = 24'hFF3030;
      2'd2:    pip_rgb = 24'h30FF30;
      default: pip_rgb = 24'h181818;
    endcase
  end
  wire pip_border = in_pip && ((pip_lx < 8'd2) || (pip_lx >= PIP_W - 2) ||
                               (pip_ly < 8'd2) || (pip_ly >= PIP_H - 2));
  logic [23:0] rgb_src;
  always_comb begin
    if (pip_border)       rgb_src = 24'hC0C0C0;
    else if (in_pip)      rgb_src = pip_rgb;
    else                  rgb_src = rgb_c;
  end

  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_src; hs_d<=hsync; vs_d<=vsync; va_d<=va; end

  assign hdmi_out_rgb   = rgb_d;
  assign hdmi_out_hsync = hs_d;
  assign hdmi_out_vsync = vs_d;
  assign hdmi_out_de    = va_d;
  assign hdmi_out_clk   = clk_25m;
  assign hdmi_out_rst_n = rst_n;

  // ---- HDMI 芯片配置 ----
  hdmi_i2c u_hdmi_i2c (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),
    .sccb_scl(ddc_scl), .sccb_sda(ddc_sda)
  );
endmodule
