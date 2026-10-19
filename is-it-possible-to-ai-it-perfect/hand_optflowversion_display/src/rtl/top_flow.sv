// top_flow.sv — 升腾Pro：OV7725 采集 -> 灰度光流场 -> 左右挥手判定 -> HDMI
//   HDMI 显示半稠密运动矢量场：明显左移块=红，明显右移块=绿，其余=黑。
//   三个 LED：led_stop / led_left / led_right，带施密特迟滞防抖。
`timescale 1ns/1ps
module top_flow (
  input  logic        sys_clk,
  input  logic        sys_rst_n,
  input  logic        cam1_pclk,
  input  logic        cam1_vsync,
  input  logic        cam1_href,
  input  logic [7:0]  cam1_data,
  output logic        cam_rst_n,
  output logic        cam_pwdn,
  output logic        sccb1_scl,
  inout  wire         sccb1_sda,
  output logic        ddc_scl,
  inout  wire         ddc_sda,
  output logic        hdmi_out_clk,
  output logic        hdmi_out_rst_n,
  output logic        hdmi_out_hsync,
  output logic        hdmi_out_vsync,
  output logic        hdmi_out_de,
  output logic [23:0] hdmi_out_rgb,
  output logic        led_stop,
  output logic        led_left,
  output logic        led_right
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

  // ---- RGB565 -> 灰度 ----
  logic [7:0] cur_gray;
  rgb2gray u_gray (.pixel(cam_wr_data), .gray(cur_gray));

  // ---- LK 光流 ----
  logic        flow_valid;
  logic signed [31:0] flow_u, flow_v;
  logic [31:0] flow_energy;
  logic [4:0]  flow_bx;
  logic [3:0]  flow_by;
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

  // ---- 矢量汇总 + 手势 FSM + 显示标签 ----
  logic [1:0] tag_out;
  flow_fsm u_fsm (
    .pclk(cam1_pclk), .rst_n(rst_n),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by),
    .vsync(cam1_vsync),
    .clk_disp(clk_25m), .px(px), .py(py), .tag_out(tag_out),
    .led_stop(led_stop), .led_left(led_left), .led_right(led_right)
  );

  // ---- 运动矢量场可视化：左=红，右=绿 ----
  logic [23:0] rgb_c;
  always_comb begin
    if (va) begin
      case (tag_out)
        2'd1:    rgb_c = 24'hFF2020;
        2'd2:    rgb_c = 24'h20FF20;
        default: rgb_c = 24'h000000;
      endcase
    end else begin
      rgb_c = 24'h000000;
    end
  end

  logic [23:0] rgb_d;
  logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
      rgb_d <= 24'd0; hs_d <= 1'b0; vs_d <= 1'b0; va_d <= 1'b0;
    end else begin
      rgb_d <= rgb_c; hs_d <= hsync; vs_d <= vsync; va_d <= va;
    end
  end

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
