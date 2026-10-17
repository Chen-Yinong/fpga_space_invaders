// top_cam_test.sv — 摄像头预览调试顶层：摄像头画面直接显示到 HDMI
`timescale 1ns/1ps
module top_cam_test (
  input  logic        sys_clk,        // W19
  input  logic        sys_rst_n,      // N15
  input  logic        key0,           // V17(不用)
  input  logic        cam1_pclk,      // AA21
  input  logic        cam1_vsync,     // T18
  input  logic        cam1_href,      // T21
  input  logic [7:0]  cam1_data,      // N14 N13 R19 P19 U22 AA20 R18 U21
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

  logic        cam_cfg_done, cam_wr_en; logic [15:0] cam_wr_data;
  ov7725_top u_cam (
    .sys_clk(clk_25m), .sys_rst_n(rst_n), .sys_init_done(cam_cfg_done),
    .ov7725_pclk(cam1_pclk), .ov7725_href(cam1_href), .ov7725_vsync(cam1_vsync), .ov7725_data(cam1_data),
    .cfg_done(cam_cfg_done), .sccb_scl(sccb1_scl), .sccb_sda(sccb1_sda),
    .ov7725_wr_en(cam_wr_en), .ov7725_data_out(cam_wr_data)
  );

  logic [11:0] px, py; logic hsync, vsync, va, fs;
  vga_timing u_vga (.clk_pix(clk_25m), .rst_n(rst_n), .x(px), .y(py),
                    .hsync(hsync), .vsync(vsync), .video_active(va), .frame_start(fs));

  logic [23:0] rgb_c;
  cam_preview u_prev (
    .pclk(cam1_pclk), .rst_n(rst_n), .pixel_en(cam_wr_en), .pixel(cam_wr_data), .cfg_done(cam_cfg_done),
    .href(cam1_href), .vsync(cam1_vsync),
    .clk_disp(clk_25m), .rx(px[9:0]), .ry(py[9:0]), .rgb(rgb_c)
  );

  logic [23:0] rgb_d; logic hs_d, vs_d, va_d;
  always_ff @(posedge clk_25m or negedge rst_n)
    if (!rst_n) begin rgb_d<='0; hs_d<=1'b0; vs_d<=1'b0; va_d<=1'b0; end
    else begin rgb_d<=rgb_c; hs_d<=hsync; vs_d<=vsync; va_d<=va; end
  assign hdmi_out_rgb=rgb_d; assign hdmi_out_hsync=hs_d; assign hdmi_out_vsync=vs_d;
  assign hdmi_out_de=va_d; assign hdmi_out_clk=clk_25m; assign hdmi_out_rst_n=rst_n;

  hdmi_i2c u_hdmi_i2c (.sys_clk(clk_25m), .sys_rst_n(rst_n), .cfg_done(),
                       .sccb_scl(ddc_scl), .sccb_sda(ddc_sda));
endmodule