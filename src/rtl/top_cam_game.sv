// top_cam_game.sv — 升腾Pro：OV7725 手势 + 肤色标定 + 太空侵略者 + HDMI
//   key0(V17)=开始/暂停   key1(W17)=肤色采样
//   右上角小窗显示摄像头(肤色标绿)
`timescale 1ns/1ps
module top_cam_game #(
  parameter int WIN_X0 = 480,   // 预览窗口(显示坐标)
  parameter int WIN_Y0 = 32,
  parameter int WIN_W  = 160,
  parameter int WIN_H  = 120
)(
  input  logic        sys_clk,        // W19 50MHz
  input  logic        sys_rst_n,      // N15
  input  logic        key0,           // V17 开始/暂停
  input  logic        key1,           // W17 肤色采样
  input  logic        cam1_pclk,      // AA21
  input  logic        cam1_vsync,     // T18
  input  logic        cam1_href,      // T21
  input  logic [7:0]  cam1_data,      // N14..U21
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
  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (.clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked));
  assign cam_rst_n = 1'b1;
  assign cam_pwdn  = 1'b0;

  // ---------------- 摄像头（OV7725）----------------
  logic        cam_cfg_done, cam_wr_en; logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href), .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  // ---------------- RGB -> YCbCr ----------------
  logic [7:0] r8, g8, b8; logic signed [11:0] cb, cr;
  rgb2ycrcb u_ycc (.pixel(cam_wr_data), .r8(r8), .g8(g8), .b8(b8), .cb(cb), .cr(cr));

  // ---------------- 按键消抖 ----------------
  logic btn_start, calib_btn_sys;
  debounce #(.CNT(250000)) u_d0 (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key0), .btn_out(btn_start));
  debounce #(.CNT(250000)) u_d1 (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key1), .btn_out(calib_btn_sys));

  // 标定按键跨到摄像头域（电平，2FF）
  logic kb1, kb2;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) begin kb1<=1'b0; kb2<=1'b0; end else begin kb1<=calib_btn_sys; kb2<=kb1; end
  logic calib_btn_p; assign calib_btn_p = kb2;

  // ---------------- 摄像头像素坐标（供标定 ROI 使用）----------------
  logic [11:0] cpx, cpy; logic chref_d, cvsync_d;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) begin cpx<='0; cpy<='0; chref_d<=1'b0; cvsync_d<=1'b0; end
    else begin
      chref_d<=cam1_href; cvsync_d<=cam1_vsync;
      if (cam1_vsync & ~cvsync_d)      begin cpx<='0; cpy<='0; end
      else if (cam1_href & ~chref_d)   begin cpx<='0; cpy<=cpy+1'b1; end
      else if (cam_wr_en)              begin cpx<=cpx+1'b1; end
    end

  // ---------------- 肤色标定 ----------------
  logic [7:0] cb_lo, cb_hi, cr_lo, cr_hi;
  logic calib_done, calib_busy;
  skin_calib u_cal (
    .pclk(cam1_pclk), .rst_n(rst_n),
    .pixel_en(cam_wr_en), .cb(cb), .cr(cr),
    .px(cpx), .py(cpy),
    .vsync(cam1_vsync), .calib_btn(calib_btn_p),
    .cb_lo(cb_lo), .cb_hi(cb_hi), .cr_lo(cr_lo), .cr_hi(cr_hi),
    .calib_done(calib_done), .calib_busy(calib_busy)
  );

  // ---------------- 肤色判定 ----------------
  logic skin_raw, skin;
  always_comb skin_raw = (cb >= $signed({4'b0000,cb_lo})) && (cb <= $signed({4'b0000,cb_hi})) &&
                         (cr >= $signed({4'b0000,cr_lo})) && (cr <= $signed({4'b0000,cr_hi}));
  // 未完成采样前，一律不算肤色
  always_comb skin = calib_done && skin_raw;

  // ---------------- 手势 ----------------
  logic [1:0] gest_cmd_p;
  vision_gesture #(.K_PIX(6), .MIN_PIX(2000)) u_vis (
    .pclk(cam1_pclk), .rst_n(rst_n),
    .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync), .move_cmd(gest_cmd_p)
  );

  // 手势 -> 游戏域（2bit 慢速，逐位 2FF）
  logic [1:0] gs1, gs2;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin gs1<='0; gs2<='0; end else begin gs1<=gest_cmd_p; gs2<=gs1; end
  logic [1:0] move_cmd; assign move_cmd = gs2;

  // 标定状态 -> 显示域（框颜色：红=未标定 黄=采样中 绿=完成）
  logic cd1, cd2, cb1, cb2;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin cd1<=1'b0; cd2<=1'b0; cb1<=1'b0; cb2<=1'b0; end
    else begin cd1<=calib_done; cd2<=cd1; cb1<=calib_busy; cb2<=cb1; end
  // 标定完成 -> 游戏域（未采样不允许开始）
  logic cds1, cds2;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin cds1<=1'b0; cds2<=1'b0; end
    else begin cds1<=calib_done; cds2<=cds1; end
  logic btn_start_g;
  assign btn_start_g = btn_start & cds2;

  // ---------------- 游戏核心 ----------------
  localparam int PSLOTS=6, ESLOTS=3;
  logic [8:0] g_px; logic g_pvis;
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;
  logic [49:0] g_ea; logic [8:0] g_ex0, g_ey0;
  logic [15:0] g_score; logic [3:0] g_lives; logic [2:0] g_wave; logic [1:0] g_state;

  game_core #(.TICK_DIV(833333), .MOVE_PERIOD(30), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (
    .clk_sys(sys_clk), .rst_n(rst_n), .move_cmd(move_cmd), .btn_start(btn_start_g),
    .player_x(g_px), .player_visible(g_pvis),
    .pb_valid(g_pbv), .pb_x(g_pbx), .pb_y(g_pby),
    .eb_valid(g_ebv), .eb_x(g_ebx), .eb_y(g_eby),
    .enemy_alive(g_ea), .enemy_x0(g_ex0), .enemy_y0(g_ey0),
    .score(g_score), .lives(g_lives), .wave(g_wave), .state(g_state)
  );

  // ---------------- 信箱 CDC: sys_clk -> clk_25m ----------------
  logic [11:0] refresh_cnt; logic bus_toggle;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin refresh_cnt<='0; bus_toggle<=1'b0; end
    else if (refresh_cnt==12'd4095) begin refresh_cnt<='0; bus_toggle<=~bus_toggle; end
    else refresh_cnt<=refresh_cnt+1'b1;

  logic t1,t2,t2_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin t1<=1'b0; t2<=1'b0; t2_d<=1'b0; end
    else begin t1<=bus_toggle; t2<=t1; t2_d<=t2; end

  logic [8:0] p_px; logic p_pvis;
  logic [PSLOTS-1:0]   p_pbv; logic [PSLOTS*9-1:0] p_pbx, p_pby;
  logic [ESLOTS-1:0]   p_ebv; logic [ESLOTS*9-1:0] p_ebx, p_eby;
  logic [49:0] p_ea; logic [8:0] p_ex0, p_ey0;
  logic [15:0] p_score; logic [3:0] p_lives; logic [2:0] p_wave; logic [1:0] p_state;

  always_ff @(posedge clk_25m or negedge rst_n)
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

  // ---------------- VGA + 渲染 ----------------
  logic [11:0] px, py; logic hsync, vsync, va, fs;
  vga_timing u_vga (.clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
                    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs));

  logic [23:0] game_rgb;
  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (
    .vid_x(px[9:0]), .vid_y(py[9:0]),
    .player_x(p_px), .player_visible(p_pvis),
    .pb_valid(p_pbv), .pb_x(p_pbx), .pb_y(p_pby),
    .eb_valid(p_ebv), .eb_x(p_ebx), .eb_y(p_eby),
    .enemy_alive(p_ea), .enemy_x0(p_ex0), .enemy_y0(p_ey0),
    .score(p_score), .lives(p_lives), .wave(p_wave),
    .rgb(game_rgb)
  );

  // ---------------- 摄像头预览：标定中全屏，否则小窗 ----------------
  logic        in_win, border;
  logic [9:0]  wx, wy;
  logic [17:0] raddr;
  logic [8:0]  fcol, frow;
  always_comb begin
    wx = px[9:0] - WIN_X0[9:0];
    wy = py[9:0] - WIN_Y0[9:0];
    in_win = (px >= WIN_X0) && (px < WIN_X0+WIN_W) && (py >= WIN_Y0) && (py < WIN_Y0+WIN_H);
    border = in_win && ((wx < 2) || (wx >= WIN_W-2) || (wy < 2) || (wy >= WIN_H-2));
    fcol = (px >= 10'd640) ? 9'd319 : px[9:1];
    frow = (py >= 10'd480) ? 9'd239 : py[8:1];
    if (cb2)
      raddr = ({8'b0, frow} * 17'd320) + {8'b0, fcol};   // 全屏预览
    else
      raddr = (({8'b0, wy} << 1) * 18'd320) + ({8'b0, wx} << 1);   // 小窗
  end

  logic [23:0] cam_rd;
  cam_frame_buf #(.DW(320), .DH(240)) u_buf (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .pixel(cam_wr_data),
    .skin(skin), .href(cam1_href), .vsync(cam1_vsync),
    .clk_disp(clk_25m), .raddr(raddr), .rd(cam_rd)
  );

  // 输出流水（game/cam/窗口/标定标志都延 1 拍）
  logic [23:0] game_d, cam_d; logic win_d, brd_d, calib_d;
  logic [9:0] wx_d, wy_d;
  logic [11:0] px_d, py_d;
  logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin
      game_d<='0; cam_d<='0; win_d<=1'b0; brd_d<=1'b0; calib_d<=1'b0;
      wx_d<='0; wy_d<='0; px_d<='0; py_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0;
    end else begin
      game_d<=game_rgb; cam_d<=cam_rd; win_d<=in_win; brd_d<=border; calib_d<=cb2;
      wx_d<=wx; wy_d<=wy; px_d<=px; py_d<=py;
      hs_d<=hsync; vs_d<=vsync; va_d<=va;
    end

  // 小窗内的标定框（游戏态用）
  wire roi_box = win_d && (wx_d >= 10'd60) && (wx_d < 10'd100) && (wy_d >= 10'd40) && (wy_d < 10'd80) &&
                 ((wx_d == 10'd60) || (wx_d == 10'd99) || (wy_d == 10'd40) || (wy_d == 10'd79));

  // 全屏标定框（标定态用）：摄像头 [240,400)x[160,320)
  wire roi_full = (px_d >= 12'd240) && (px_d < 12'd400) && (py_d >= 12'd160) && (py_d < 12'd320);
  wire roi_full_edge = roi_full && ((px_d == 12'd240) || (px_d == 12'd399) || (py_d == 12'd160) || (py_d == 12'd319));

  wire [23:0] roi_col = (!cd2) ? 24'hFF0000 : (cb2 ? 24'hFFFF00 : 24'h00FF00);
  logic [23:0] final_rgb;
  always_comb begin
    if (calib_d) begin
      // 标定态：全屏摄像头预览 + 大黄框
      if (roi_full_edge) final_rgb = 24'hFFFF00;
      else               final_rgb = cam_d;
    end else begin
      final_rgb = brd_d ? 24'hFFFFFF : (roi_box ? roi_col : (win_d ? cam_d : game_d));
    end
  end
  assign hdmi_out_rgb   = final_rgb;
  assign hdmi_out_hsync = hs_d;
  assign hdmi_out_vsync = vs_d;
  assign hdmi_out_de    = va_d;
  assign hdmi_out_clk   = clk_25m;
  assign hdmi_out_rst_n = rst_n;

  // ---------------- HDMI I2C ----------------
  hdmi_i2c u_hdmi_i2c (.sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),
                       .sccb_scl(ddc_scl), .sccb_sda(ddc_sda));
endmodule