// top_hand_bin.sv — 升腾Pro：OV7725 默认肤色 -> 手部二值化掩膜 -> HDMI
//   手部像素 = 白(1)，其他 = 黑(0)。用于观察默认肤色分割效果。
`timescale 1ns/1ps
module top_hand_bin (
  input  logic        sys_clk,        // W19 50MHz
  input  logic        sys_rst_n,      // N15
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
  output logic [23:0] hdmi_out_rgb,
  output logic        led_stop,       // M21 手不动
  output logic        led_left,       // L21 明显左移
  output logic        led_right       // K21 明显右移
);
  // ---- 时钟与复位 ----
  logic clk_25m, locked, rst_n;
  assign rst_n = sys_rst_n & locked;
  hdmi_pll u_pll (
    .clk_in1(sys_clk), .reset(~sys_rst_n), .clk_out1(clk_25m), .locked(locked)
  );
  assign cam_rst_n = 1'b1;
  assign cam_pwdn  = 1'b0;

  // ---- 摄像头 OV7725 采集 ----
  logic        cam_cfg_done, cam_wr_en;
  logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href),
    .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  // ---- RGB565 -> YCbCr ----
  logic [7:0] r8, g8, b8;
  logic signed [11:0] cb, cr;
  rgb2ycrcb u_ycc (
    .pixel(cam_wr_data), .r8(r8), .g8(g8), .b8(b8), .cb(cb), .cr(cr)
  );

// ---- 平衡型肤色判定（压制背景杂色 + 保留高光手掌）----
  wire [8:0] cbu = cb[8:0];
  wire [8:0] cru = cr[8:0];
  wire [8:0] dcb = (cbu >= 9'd128) ? (cbu - 9'd128) : (9'd128 - cbu);
  wire [8:0] dcr = (cru >= 9'd128) ? (cru - 9'd128) : (9'd128 - cru);
  
  // 1. 基础肤色：暖色阈值提升到 20，饱和度维持 10
  wire sat_ok    = (dcb + dcr) >= 10'd10;
  wire signed [12:0] cr_cb = cr - cb;
  wire warm_ok   = (cr_cb >= 13'sd20);              // 阻挡发黄的木质桌面
  wire base_skin = (cb >= 12'sd92)  && (cb <= 12'sd128) &&
                   (cr >= 12'sd135) && (cr <= 12'sd180) &&
                   sat_ok && warm_ok;

  // 2. 严格高光补偿：只对真正过曝的肉色生效，排除暗黄色杂物
  wire highlight_skin = (r8 >= 8'd215) && (g8 >= 8'd160) && 
                        (r8 >= g8) && (r8 > (b8 + 8'd20));

  wire skin_raw = base_skin || highlight_skin;

  // ---- 消除背景孤立单点噪点（全图 1D 腐蚀）----
  logic skin_d1;
  always_ff @(posedge cam1_pclk or negedge rst_n) begin
    if (!rst_n)
      skin_d1 <= 1'b0;
    else if (cam_wr_en)
      skin_d1 <= skin_raw; // 直接吃原始肤色
  end

  logic skin;
  assign skin = skin_raw && skin_d1; // 连续两点有效才计为手部

  // ---- 手部质心计算（摄像头时钟域）----
  logic        centroid_valid;
  logic [9:0]  centroid_cx;
  logic [8:0]  centroid_cy;
  logic signed [10:0] centroid_dx;
  centroid_calc u_cent (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .valid(centroid_valid), .cx(centroid_cx), .cy(centroid_cy), .dx(centroid_dx)
  );

// ---- 防抖手势判定 + LED 指示状态机 ----
  // 1. 寄存器与状态机变量声明（补回漏掉的声明）
  logic led_stop_r, led_left_r, led_right_r;

  typedef enum logic [1:0] {
    ST_IDLE,    // 00: 停止 / 无手
    ST_LEFT,    // 01: 稳定向左
    ST_RIGHT    // 10: 稳定向右
  } hand_state_e;

  hand_state_e current_state;
  logic [2:0]  stop_cnt; // 退出缓冲计数器

  // 2. 抓取帧结束脉冲（确保状态机按帧率更新）
  logic vsync_d2;
  always_ff @(posedge cam1_pclk or negedge rst_n) begin
    if (!rst_n) vsync_d2 <= 1'b0;
    else        vsync_d2 <= cam1_vsync;
  end
  wire frame_tick = cam1_vsync && !vsync_d2; // 每一帧结算一次状态

  // 3. 双阈值（施密特迟滞）定义
  localparam signed [10:0] TH_FAST = 11'sd9;  // 触发启动移动的门槛（像素/帧）
  localparam signed [10:0] TH_SLOW = 11'sd4;  // 维持移动的最低底线（跌破此值才考虑停止）
  localparam [2:0]          HOLD_MAX = 3'd3;   // 连续保持 3 帧静止才退回停止态

  always_ff @(posedge cam1_pclk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= ST_IDLE;
      stop_cnt      <= 3'd0;
      led_stop_r    <= 1'b0;
      led_left_r    <= 1'b0;
      led_right_r   <= 1'b0;
    end else if (frame_tick) begin
      if (!centroid_valid) begin
        // 画面中完全没手：熄灭所有灯
        current_state <= ST_IDLE;
        stop_cnt      <= 3'd0;
        led_stop_r    <= 1'b0;
        led_left_r    <= 1'b0;
        led_right_r   <= 1'b0;
      end else begin
        // 画面有手：执行三态消抖状态机
        case (current_state)
          ST_IDLE: begin
            stop_cnt <= 3'd0;
            if (centroid_dx < -TH_FAST)
              current_state <= ST_LEFT;
            else if (centroid_dx > TH_FAST)
              current_state <= ST_RIGHT;
          end

          ST_LEFT: begin
            if (centroid_dx < -TH_SLOW) begin
              stop_cnt <= 3'd0;
            end else if (centroid_dx > TH_FAST) begin
              current_state <= ST_RIGHT;
              stop_cnt      <= 3'd0;
            end else begin
              if (stop_cnt >= HOLD_MAX) begin
                current_state <= ST_IDLE;
                stop_cnt      <= 3'd0;
              end else begin
                stop_cnt <= stop_cnt + 1'b1;
              end
            end
          end

          ST_RIGHT: begin
            if (centroid_dx > TH_SLOW) begin
              stop_cnt <= 3'd0;
            end else if (centroid_dx < -TH_FAST) begin
              current_state <= ST_LEFT;
              stop_cnt      <= 3'd0;
            end else begin
              if (stop_cnt >= HOLD_MAX) begin
                current_state <= ST_IDLE;
                stop_cnt      <= 3'd0;
              end else begin
                stop_cnt <= stop_cnt + 1'b1;
              end
            end
          end
        endcase

        // 最终驱动 LED
        led_left_r  <= (current_state == ST_LEFT);
        led_right_r <= (current_state == ST_RIGHT);
        led_stop_r  <= (current_state == ST_IDLE);
      end
    end
  end

  assign led_stop  = led_stop_r;
  assign led_left  = led_left_r;
  assign led_right = led_right_r;


  // ---- VGA 时序 ----
  logic [11:0] px, py;
  logic hsync, vsync, va, fs;
  vga_timing u_vga (
    .clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs)
  );

  // ---- 质心跨时钟域（摄像头域 -> 显示域，2FF 同步）----
  logic        cv1, cv2;
  logic [9:0]  cx1, cx2;
  logic [8:0]  cy1, cy2;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin
      cv1<=1'b0; cv2<=1'b0; cx1<='0; cx2<='0; cy1<='0; cy2<='0;
    end else begin
      cv1<=centroid_valid; cv2<=cv1;
      cx1<=centroid_cx;    cx2<=cx1;
      cy1<=centroid_cy;    cy2<=cy1;
    end

  // ---- 红色十字标记（臂长 12，线宽 2）----
  wire [9:0] adx = (px[9:0] >= cx2) ? (px[9:0] - cx2) : (cx2 - px[9:0]);
  wire [8:0] ady = (py[8:0] >= cy2) ? (py[8:0] - cy2) : (cy2 - py[8:0]);
  wire cross_v = (adx <= 10'd1) && (ady <= 9'd12);
  wire cross_h = (ady <= 9'd1) && (adx <= 10'd12);
  wire cross_on = cv2 && (cross_v || cross_h);

  // ---- 1bit 二值化帧缓存（320x240 抽点，显示时 2x2 放大）----
  logic bin;
  bin_frame_buf u_buf (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .skin(skin),
    .href(cam1_href), .vsync(cam1_vsync),
    .clk_disp(clk_25m), .rdx(px[9:1]), .rdy(py[8:1]),
    .bin_out(bin)
  );

  // ---- 二值化 -> RGB（手=白，其他=黑）----
  logic [23:0] rgb_c;
  assign rgb_c = (va && cross_on) ? 24'hFF0000 : ((va && bin) ? 24'hFFFFFF : 24'h000000);

  logic [23:0] rgb_d;
  logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_c; hs_d<=hsync; vs_d<=vsync; va_d<=va; end

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
