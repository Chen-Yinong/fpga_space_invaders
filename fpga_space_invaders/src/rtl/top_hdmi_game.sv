// top_hdmi_game.sv
// 升腾Pro（野火 A7_Pro, XC7A100T-FGG484-2）顶层：按键游戏 + HDMI 输出
//   sys_clk 50MHz -> PLL -> 25MHz 像素时钟
//   游戏跑在 sys_clk(50MHz)；显示跑在 clk_pix(25MHz)，中间用信箱跨时钟域
//   HDMI 芯片用 I2C 配置（板载例程 hdmi_i2c）
// 注意：需要在 Vivado 里生成一个 PLL IP，命名为 hdmi_pll：50MHz 输入 -> 25MHz 输出
`timescale 1ns/1ps
module top_hdmi_game (
  input  logic        sys_clk,        // W19  50MHz
  input  logic        sys_rst_n,      // N15
  input  logic [3:0]  key,            // V17 W17 AA18 AB18  (key0=左 key1=右 key2=开始/暂停 key3=发射)
  output logic        ddc_scl,        // E19
  inout  wire         ddc_sda,        // D19
  output logic        hdmi_out_clk,   // K18
  output logic        hdmi_out_rst_n, // J16
  output logic        hdmi_out_hsync, // K17
  output logic        hdmi_out_vsync, // J17
  output logic        hdmi_out_de,    // K19
  output logic [23:0] hdmi_out_rgb    // H13..K16
);
  logic clk_pix, locked, rst_n;
  assign rst_n = sys_rst_n & locked;

  // 50MHz -> 25MHz 像素时钟（Vivado 里生成 IP：hdmi_pll）
  hdmi_pll u_pll (
    .clk_in1 (sys_clk),
    .reset   (~sys_rst_n),
    .clk_out1(clk_pix),
    .locked  (locked)
  );

  // 游戏 + 消抖 + 跨时钟域 + VGA时序 + 渲染（复用 top_button_game）
  top_button_game #(
    .TICK_DIV    (833333),   // 50MHz / 60Hz
    .MOVE_PERIOD (30),
    .DEB_CNT     (250000)    // 5ms @50MHz
  ) u_game (
    .clk_sys        (sys_clk),
    .clk_pix        (clk_pix),
    .rst_n          (rst_n),
    .btn_left_raw   (~key[0]),   // 板载按键低有效
    .btn_right_raw  (~key[1]),
    .btn_start_raw  (~key[2]),
    .vga_rgb        (hdmi_out_rgb),
    .vga_hsync      (hdmi_out_hsync),
    .vga_vsync      (hdmi_out_vsync),
    .vga_de         (hdmi_out_de)
  );

  // 板载 HDMI 芯片 I2C 配置
  hdmi_i2c u_hdmi_i2c (
    .sys_clk  (clk_pix),
    .sys_rst_n(sys_rst_n),
    .cfg_done (),
    .sccb_scl (ddc_scl),
    .sccb_sda (ddc_sda)
  );

  assign hdmi_out_clk   = clk_pix;
  assign hdmi_out_rst_n = rst_n;
endmodule