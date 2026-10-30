// top_cam_game.sv — 完全体：OV7725 手势方向控制 + 太空侵略者 + HDMI
//   右上角画中画实时显示二值化手势画面 + 红色十字准星
//   key2(AA18)=开始/暂停/继续  key3(AB18)=重开；左右由摄像头手势控制
`timescale 1ns/1ps
module top_cam_game (
  input  logic        sys_clk,        // W19 50MHz
  input  logic        sys_rst_n,      // N15
  input  logic        cam1_pclk,      // AA21
  input  logic        cam1_vsync,     // T18
  input  logic        cam1_href,      // T21
  input  logic [7:0]  cam1_data,      // N14..U21
  input  logic        key2,           // AA18
  input  logic        key3,           // AB18
  output logic        cam_rst_n,      // P16
  output logic        cam_pwdn,       // R17
  output logic        sccb1_scl,      // R14
  inout  wire         sccb1_sda,      // P14
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
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=16;
  localparam int WIN_X0=480, WIN_Y0=32, WIN_W=160, WIN_H=120;   // 画中画(显示坐标)

  // ---- 时钟与复位 ----
  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)
  );
  assign cam_rst_n = 1'b1;
  assign cam_pwdn  = 1'b0;

  // ---- OV7725 采集 ----
  logic cam_cfg_done, cam_wr_en; logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href),
    .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  // ---- RGB565 -> YCbCr ----
  logic [7:0] r8, g8, b8; logic signed [11:0] cb, cr;
  rgb2ycrcb u_ycc (
    .pixel(cam_wr_data), .r8(r8), .g8(g8), .b8(b8), .cb(cb), .cr(cr)
  );

  // ---- 平衡型肤色判定 + 1D 腐蚀去噪（同 hand_bin_display）----
  wire [8:0] cbu = cb[8:0];
  wire [8:0] cru = cr[8:0];
  wire [8:0] dcb = (cbu >= 9'd128) ? (cbu - 9'd128) : (9'd128 - cbu);
  wire [8:0] dcr = (cru >= 9'd128) ? (cru - 9'd128) : (9'd128 - cru);
  wire       sat_ok  = (dcb + dcr) >= 10'd10;
  wire signed [12:0] cr_cb = cr - cb;
  wire       warm_ok = (cr_cb >= 13'sd20);
  wire base_skin = (cb >= 12'sd92) && (cb <= 12'sd128) &&
                   (cr >= 12'sd135) && (cr <= 12'sd180) && sat_ok && warm_ok;
  wire highlight_skin = (r8 >= 8'd215) && (g8 >= 8'd160) &&
                        (r8 >= g8) && (r8 > (b8 + 8'd20));
  wire skin_raw = base_skin || highlight_skin;
  logic skin_d1;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) skin_d1 <= 1'b0;
    else if (cam_wr_en) skin_d1 <= skin_raw;
  logic skin;
  assign skin = skin_raw && skin_d1;

  // ---- 质心与帧间位移 ----
  logic centroid_valid; logic [9:0] centroid_cx; logic [8:0] centroid_cy;
  logic signed [10:0] centroid_dx;
  centroid_calc u_cent (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .valid(centroid_valid), .cx(centroid_cx), .cy(centroid_cy), .dx(centroid_dx)
  );

  // ---- 方向判定（摄像头域）----
  logic vsync_d1;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) vsync_d1 <= 1'b0;
    else        vsync_d1 <= cam1_vsync;
  wire frame_tick = cam1_vsync && !vsync_d1;

  logic dir_left_p, dir_right_p;
  dir_judge u_dir (
    .pclk(cam1_pclk), .rst_n(rst_n), .frame_tick(frame_tick),
    .valid(centroid_valid), .dx(centroid_dx),
    .move_left(dir_left_p), .move_right(dir_right_p)
  );

  // ---- 方向电平跨到 sys_clk 域（2FF）----
  logic dl1, dl2, dr1, dr2;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin dl1<=1'b0; dl2<=1'b0; dr1<=1'b0; dr2<=1'b0; end
    else begin dl1<=dir_left_p; dl2<=dl1; dr1<=dir_right_p; dr2<=dr1; end
  wire move_left  = dl2;
  wire move_right = dr2;

  // ---- 按键消抖（key2/key3）----
  logic btn_s, btn_re;
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));

  // ---- 游戏核心 ----
  logic [8:0]  g_px; logic g_pvis;
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;
  logic [FORM_COLS*FORM_ROWS-1:0] g_ea; logic [8:0] g_ex0, g_ey0;
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] g_bunk;
  logic [15:0] g_score; logic [3:0] g_lives; logic [1:0] g_state;
  logic g_win; logic g_ufo_act; logic [8:0] g_ufo_x;
  logic [1:0] g_stage; logic g_stage_show, g_stage_blink;

  game_core #(.TICK_DIV(833333), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS),
            .BUNKERS(BUNKERS), .BUNK_W(BUNK_W), .BUNK_H(BUNK_H), .LIVES_INIT(6)) u_game (
    .clk_sys(sys_clk), .rst_n(rst_n),
    .btn_left(move_right), .btn_right(move_left), //觉得左右镜像这个不爽就对调这里
    .btn_start(btn_s), .btn_restart(btn_re),
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
  logic p_win; logic p_ufo_act; logic [8:0] p_ufo_x;
  logic [1:0] p_stage; logic p_stage_show, p_stage_blink;

  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin
      p_px<='0; p_pvis<=1'b1; p_pbv<='0; p_pbx<='0; p_pby<='0;
      p_ebv<='0; p_ebx<='0; p_eby<='0; p_ea<='0; p_ex0<='0; p_ey0<='0;
      p_bunk<='1; p_score<='0; p_lives<='0; p_state<='0;
      p_win<=1'b0; p_ufo_act<=1'b0; p_ufo_x<='0;
      p_stage<=2'd0; p_stage_show<=1'b0; p_stage_blink<=1'b0;
    end else if (t2 != t2_d) begin
      p_px<=g_px; p_pvis<=g_pvis;
      p_pbv<=g_pbv; p_pbx<=g_pbx; p_pby<=g_pby;
      p_ebv<=g_ebv; p_ebx<=g_ebx; p_eby<=g_eby;
      p_ea<=g_ea; p_ex0<=g_ex0; p_ey0<=g_ey0;
      p_bunk<=g_bunk; p_score<=g_score; p_lives<=g_lives; p_state<=g_state;
      p_win<=g_win; p_ufo_act<=g_ufo_act; p_ufo_x<=g_ufo_x;
      p_stage<=g_stage; p_stage_show<=g_stage_show; p_stage_blink<=g_stage_blink;
    end

  // ---- VGA 时序 + 游戏渲染 ----
  logic [11:0] px, py; logic hsync, vsync, va, fs;
  vga_timing u_vga (
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)
  );

  logic [23:0] game_rgb;
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS),
                .BUNKERS(BUNKERS), .BUNK_W(BUNK_W), .BUNK_H(BUNK_H)) u_render (
    .vid_x(px[9:0]), .vid_y(py[9:0]),
    .player_x(p_px), .player_visible(p_pvis),
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),
    .bunker_bits(p_bunk), .score(p_score), .lives(p_lives), .state(p_state),
    .win(p_win), .ufo_active(p_ufo_act), .ufo_x(p_ufo_x),
    .stage(p_stage), .stage_show(p_stage_show), .stage_blink(p_stage_blink),
    .rgb(game_rgb)
  );

  // ---- 画中画：右上角小窗显示二值化手势 ----
  wire in_win = (px >= WIN_X0) && (px < WIN_X0+WIN_W) && (py >= WIN_Y0) && (py < WIN_Y0+WIN_H);
  wire [8:0] wx = px[8:0] - WIN_X0[8:0];   // 0..159
  wire [7:0] wy = py[7:0] - WIN_Y0[7:0];   // 0..119
  logic bin;
  bin_frame_buf u_buf (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .clk_disp(clk_25m), .rdx(wx << 1), .rdy(wy << 1),
    .bin_out(bin)
  );

  // ---- 质心同步到显示域 + 红色十字准星 ----
  logic [9:0] cx1, cx2; logic [8:0] cy1, cy2;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin cx1<='0; cx2<='0; cy1<='0; cy2<='0; end
    else begin cx1<=centroid_cx; cx2<=cx1; cy1<=centroid_cy; cy2<=cy1; end

  wire [7:0] cross_wx = cx2[9:2];   // 小窗内坐标 = 全分辨率质心 / 4
  wire [6:0] cross_wy = cy2[8:2];
  wire [9:0] cross_sx = WIN_X0[9:0] + cross_wx;   // 屏幕坐标
  wire [8:0] cross_sy = WIN_Y0[8:0] + cross_wy;
  wire [9:0] adx = (px[9:0] >= cross_sx) ? (px[9:0] - cross_sx) : (cross_sx - px[9:0]);
  wire [8:0] ady = (py[8:0] >= cross_sy) ? (py[8:0] - cross_sy) : (cross_sy - py[8:0]);
  wire cross_on = in_win && (((adx <= 10'd1) && (ady <= 9'd10)) || ((ady <= 9'd1) && (adx <= 10'd10)));

  // ---- 画面合成：小窗内显示手势二值化 + 十字，其余显示游戏 ----
  wire [23:0] win_rgb = cross_on ? 24'hFF0000 : (bin ? 24'hFFFFFF : 24'h000000);
  wire [23:0] rgb_pre = in_win ? win_rgb : game_rgb;

  // ---- 输出流水 ----
  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_pre; hs_d<=hsync; vs_d<=vsync; va_d<=va; end

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
