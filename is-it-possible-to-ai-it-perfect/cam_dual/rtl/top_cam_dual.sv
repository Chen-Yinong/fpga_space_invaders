// top_cam_dual.sv — 双模式合并版：LK 光流 与 肤色质心 二选一
//   两套视觉前端同时运行（共用同一路摄像头数据流），只在 pclk 域的
//   “向左/向右”出口做二选一，后面的 2FF 同步器、信箱 CDC、game_core、
//   sprite_render 全部共用 —— 因此跨时钟域结构与单模式版本完全一致。
//
//   按键：key0(V17) 切换模式（仅在待机 IDLE 时生效，切换即全量复位）
//         key2(AA18) 开始/暂停/继续
//         key3(AB18) 重开
//
//   LED ：led_left  亮 = 光流模式
//         led_right 亮 = 肤色质心模式
//         led_stop  恒灭（保留原引脚）
//
//   画中画：右上角 472,8 起 160x120
//         光流模式 = 矢量场（红=左 / 绿=右 / 深灰=静止）
//         质心模式 = 二值化手势轮廓（白=肤色）+ 红色十字准星
`timescale 1ns/1ps
module top_cam_dual (
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
  // 按键
  input  logic        key0,           // V17  模式切换
  input  logic        key2,           // AA18 开始/暂停
  input  logic        key3,           // AB18 重开
  // HDMI
  output logic        ddc_scl,        // E19
  inout  wire         ddc_sda,        // D19
  output logic        hdmi_out_clk,   // K18
  output logic        hdmi_out_rst_n, // J16
  output logic        hdmi_out_hsync, // K17
  output logic        hdmi_out_vsync, // J17
  output logic        hdmi_out_de,    // K19
  output logic [23:0] hdmi_out_rgb,
  // 指示 LED
  output logic        led_stop,       // M21
  output logic        led_left,       // L21
  output logic        led_right       // K21
);
  localparam int PSLOTS=6, ESLOTS=6, FORM_COLS=11, FORM_ROWS=5;
  localparam int BUNKERS=4, BUNK_W=24, BUNK_H=12;

  // ==== 肤色判据参数（与质心版一致，固定曝光下如需微调只改这里）====
  localparam signed [11:0] CB_LO = 12'sd92,  CB_HI = 12'sd128;
  localparam signed [11:0] CR_LO = 12'sd135, CR_HI = 12'sd180;
  localparam signed [12:0] WARM_MIN = 13'sd20;   // Cr-Cb 下限

  // ---- 时钟与复位 ----
  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)
  );
  assign cam_rst_n = 1'b1;
  assign cam_pwdn  = 1'b0;

  // ---- 摄像头采集（两种模式共用）----
  logic cam_cfg_done, cam_wr_en;
  logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href),
    .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  // ================= 分支 A：LK 光流 =================
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

  // 画中画窗口（两种模式共用同一位置，保证切换时画面不跳）
  localparam int PIP_X0 = 472, PIP_Y0 = 8, PIP_W = 160, PIP_H = 120;

  logic gest_left, gest_right;
  logic [1:0] tag_out;
  logic [11:0] px, py;
  // flow_fsm 需要显示域坐标来渲染矢量场标签；此处在下面 VGA 产生后连入
  logic [11:0] fsm_px, fsm_py;

  flow_fsm #(.TAG_SHIFT(3)) u_fsm (
    .pclk(cam1_pclk), .rst_n(rst_n),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by),
    .vsync(cam1_vsync),
    .clk_disp(clk_25m), .px(fsm_px), .py(fsm_py), .tag_out(tag_out),
    .led_stop(), .led_left(gest_left), .led_right(gest_right)
  );

  // ================= 分支 B：肤色质心 =================
  logic [7:0] r8, g8, b8;
  logic signed [11:0] cb, cr;
  rgb2ycrcb u_ycc (
    .pixel(cam_wr_data), .r8(r8), .g8(g8), .b8(b8), .cb(cb), .cr(cr)
  );

  wire [8:0] cbu = cb[8:0];
  wire [8:0] cru = cr[8:0];
  wire [8:0] dcb = (cbu >= 9'd128) ? (cbu - 9'd128) : (9'd128 - cbu);
  wire [8:0] dcr = (cru >= 9'd128) ? (cru - 9'd128) : (9'd128 - cru);
  wire       sat_ok  = (dcb + dcr) >= 10'd10;
  wire signed [12:0] cr_cb = cr - cb;
  wire       warm_ok = (cr_cb >= WARM_MIN);
  wire base_skin = (cb >= CB_LO) && (cb <= CB_HI) &&
                   (cr >= CR_LO) && (cr <= CR_HI) && sat_ok && warm_ok;
  wire highlight_skin = (r8 >= 8'd215) && (g8 >= 8'd160) &&
                        (r8 >= g8) && (r8 > (b8 + 8'd20));
  wire skin_raw = base_skin || highlight_skin;

  // 1D 水平腐蚀（与质心版一致）
  logic skin_d1;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) skin_d1 <= 1'b0;
    else if (cam_wr_en) skin_d1 <= skin_raw;
  wire skin = skin_raw && skin_d1;

  logic centroid_valid;
  logic [9:0] centroid_cx;
  logic [8:0] centroid_cy;
  logic signed [10:0] centroid_dx;
  centroid_calc u_cent (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .valid(centroid_valid), .cx(centroid_cx), .cy(centroid_cy), .dx(centroid_dx)
  );

  logic vsync_d1;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) vsync_d1 <= 1'b0;
    else        vsync_d1 <= cam1_vsync;
  wire frame_tick = cam1_vsync && !vsync_d1;

  logic dir_left_p, dir_right_p;
  dir_judge_acc u_dir (  // 慢速积分版：慢手也能动（见 dir_judge_acc.sv 顶部注释）
    .pclk(cam1_pclk), .rst_n(rst_n), .frame_tick(frame_tick),
    .valid(centroid_valid), .dx(centroid_dx),
    .move_left(dir_left_p), .move_right(dir_right_p)
  );

  // ================= 模式寄存器（sys_clk 域）=================
  logic k0_s;
  debounce #(.CNT(250000)) u_k0 (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key0), .btn_out(k0_s));

  logic k0_d;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) k0_d <= 1'b0;
    else        k0_d <= k0_s;
  wire k0_rise = k0_s & ~k0_d;

  logic mode_flow;           // 1 = 光流模式（默认，与已交付版本一致）
  logic [1:0] g_state;       // game_core 状态（0=IDLE）

  // 任意时刻都可切换：按下 key0 即换模式，并把当前这局整局复位回待机画面，
  // 再按 key2 就是新模式的第 1 局（避免“玩到一半换不了/换了状态错乱”）。
  wire mode_chg = k0_rise;

  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) mode_flow <= 1'b1;
    else if (mode_chg) mode_flow <= ~mode_flow;

  // 切换时给 game_core 一段低复位，清空分数/生命/掩体/敌阵
  logic [7:0] mrst_cnt;
  logic       mrst_n;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin mrst_cnt <= '0; mrst_n <= 1'b1; end
    else if (mode_chg) begin mrst_cnt <= 8'hFF; mrst_n <= 1'b0; end
    else if (mrst_cnt != 8'd0) mrst_cnt <= mrst_cnt - 1'b1;
    else mrst_n <= 1'b1;

  wire g_rst_n = rst_n & mrst_n;

  // ================= 方向出口二选一（pclk 域）=================
  // 摄像头为镜像输出：画面里的“左”对应现实“右”，两种模式都在这里统一对调
  logic m1, m2;
  always_ff @(posedge cam1_pclk or negedge rst_n)
    if (!rst_n) begin m1 <= 1'b1; m2 <= 1'b1; end
    else        begin m1 <= mode_flow; m2 <= m1; end

  wire v_left_p  = m2 ? gest_right : dir_right_p;   // 游戏左 = 画面右
  wire v_right_p = m2 ? gest_left  : dir_left_p;    // 游戏右 = 画面左

  // ---- 方向电平跨到 sys_clk 域（2FF，单一同步器，两种模式共用）----
  logic gl_s1, gl_s2, gr_s1, gr_s2;
  always_ff @(posedge sys_clk or negedge rst_n)
    if (!rst_n) begin gl_s1<=1'b0; gl_s2<=1'b0; gr_s1<=1'b0; gr_s2<=1'b0; end
    else begin
      gl_s1 <= v_left_p;  gl_s2 <= gl_s1;
      gr_s1 <= v_right_p; gr_s2 <= gr_s1;
    end

  // ---- 按键消抖（key2/key3，低有效）----
  logic btn_s, btn_re;
  debounce #(.CNT(250000)) u_s  (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key2), .btn_out(btn_s));
  debounce #(.CNT(250000)) u_re (.clk(sys_clk), .rst_n(rst_n), .btn_in(~key3), .btn_out(btn_re));

  // ---- 游戏核心 ----
  logic [8:0]  g_px; logic g_pvis;
  logic [PSLOTS-1:0]   g_pbv; logic [PSLOTS*9-1:0] g_pbx, g_pby;
  logic [ESLOTS-1:0]   g_ebv; logic [ESLOTS*9-1:0] g_ebx, g_eby;
  logic [FORM_COLS*FORM_ROWS-1:0] g_ea; logic [8:0] g_ex0, g_ey0;
  logic [BUNKERS*BUNK_W*BUNK_H-1:0] g_bunk;
  logic [15:0] g_score; logic [3:0] g_lives;
  logic g_ufo_act; logic [8:0] g_ufo_x;
  logic g_win;
  logic [1:0] g_stage; logic g_stage_show, g_stage_blink;

  game_core #(.TICK_DIV(833333), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_game (
    .clk_sys(sys_clk), .rst_n(g_rst_n),
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

  // ---- VGA 时序 ----
  logic hsync, vsync, va, fs;
  vga_timing u_vga (
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)
  );

  wire in_pip = (px >= PIP_X0) && (px < PIP_X0 + PIP_W) && (py >= PIP_Y0) && (py < PIP_Y0 + PIP_H);
  wire [8:0] wx = px[8:0] - PIP_X0[8:0];
  wire [7:0] wy = py[7:0] - PIP_Y0[7:0];
  assign fsm_px = in_pip ? {3'd0, wx} : 12'd0;
  assign fsm_py = in_pip ? {4'd0, wy} : 12'd0;

  // ---- 渲染 ----
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

  // ---- 画中画 A：光流矢量场（红=左 绿=右 深灰=静止）----
  logic [23:0] pip_flow;
  always_comb begin
    case (tag_out)
      2'd1:    pip_flow = 24'hFF3030;
      2'd2:    pip_flow = 24'h30FF30;
      default: pip_flow = 24'h181818;
    endcase
  end

  // ---- 画中画 B：二值轮廓 + 红色十字准星 ----
  logic bin;
  bin_frame_buf u_buf (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .clk_disp(clk_25m), .rdx(wx << 1), .rdy(wy << 1),
    .bin_out(bin)
  );

  logic [9:0] cx1, cx2; logic [8:0] cy1, cy2;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin cx1<='0; cx2<='0; cy1<='0; cy2<='0; end
    else begin cx1<=centroid_cx; cx2<=cx1; cy1<=centroid_cy; cy2<=cy1; end

  wire [7:0] cross_wx = cx2[9:2];                 // 小窗内坐标 = 全分辨率质心 / 4
  wire [6:0] cross_wy = cy2[8:2];
  wire [9:0] cross_sx = PIP_X0[9:0] + cross_wx;   // 屏幕坐标
  wire [8:0] cross_sy = PIP_Y0[8:0] + cross_wy;
  wire [9:0] adx = (px[9:0] >= cross_sx) ? (px[9:0] - cross_sx) : (cross_sx - px[9:0]);
  wire [8:0] ady = (py[8:0] >= cross_sy) ? (py[8:0] - cross_sy) : (cross_sy - py[8:0]);
  wire cross_on = in_pip && (((adx <= 10'd1) && (ady <= 9'd10)) ||
                             ((ady <= 9'd1) && (adx <= 10'd10)));

  // ---- 显示域模式同步（sys_clk -> clk_25m）----
  logic md1, md2;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin md1 <= 1'b1; md2 <= 1'b1; end
    else        begin md1 <= mode_flow; md2 <= md1; end

  wire [23:0] pip_b = cross_on ? 24'hFF0000 : (bin ? 24'hFFFFFF : 24'h000000);
  wire [23:0] pip_rgb = md2 ? pip_flow : pip_b;
  wire pip_border = in_pip && ((wx < 9'd2) || (wx >= PIP_W - 2) ||
                               (wy < 8'd2) || (wy >= PIP_H - 2));

  logic [23:0] rgb_src;
  always_comb begin
    if (pip_border)       rgb_src = 24'hC0C0C0;
    else if (in_pip)      rgb_src = pip_rgb;
    else                  rgb_src = rgb_c;
  end

  // ---- 输出流水 ----
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

  // ---- 模式指示 ----
  assign led_stop  = 1'b0;
  assign led_left  = mode_flow;      // 光流模式
  assign led_right = ~mode_flow;     // 质心模式

  // ---- HDMI 芯片配置 ----
  hdmi_i2c u_hdmi_i2c (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),
    .sccb_scl(ddc_scl), .sccb_sda(ddc_sda)
  );
endmodule