// cam_preview.sv — 摄像头预览 + 诊断
//   左上角 48x48: 随摄像头帧数变色（没有 VSYNC 就不变）
//   整屏: 红=配置未完成 蓝=没有像素数据 否则显示画面(肤色->绿)
`timescale 1ns/1ps
module cam_preview #(
  parameter int DW = 320,
  parameter int DH = 240
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic [15:0] pixel,
  input  logic        href,
  input  logic        vsync,
  input  logic        cfg_done,     // 显示域(clk_disp)的配置完成标志
  input  logic        clk_disp,
  input  logic [9:0]  rx, ry,
  output logic [23:0] rgb
);
  logic [11:0] pcnt, rcnt; logic href_d, vsync_d;
  always_ff @(posedge pclk or negedge rst_n)
    if (!rst_n) begin pcnt<='0; rcnt<='0; href_d<=1'b0; vsync_d<=1'b0; end
    else begin
      href_d<=href; vsync_d<=vsync;
      if (vsync & ~vsync_d)    begin pcnt<='0; rcnt<='0; end
      else if (href & ~href_d) begin pcnt<='0; rcnt<=rcnt+1'b1; end
      else if (pixel_en)       begin pcnt<=pcnt+1'b1; end
    end

  logic [4:0] r5; logic [5:0] g6; logic [4:0] b5;
  logic [7:0] r8, g8, b8;
  assign r5=pixel[15:11]; assign g6=pixel[10:5]; assign b5=pixel[4:0];
  assign r8={r5,r5[4:2]}; assign g8={g6,g6[5:4]}; assign b8={b5,b5[4:2]};
  logic signed [11:0] cb, cr;
  always_comb begin
    cb = 12'sd128 + (( -43*$signed({1'b0,r8}) - 85*$signed({1'b0,g8}) + 128*$signed({1'b0,b8}) ) >>> 8);
    cr = 12'sd128 + (( 128*$signed({1'b0,r8}) - 107*$signed({1'b0,g8}) -  21*$signed({1'b0,b8}) ) >>> 8);
  end
  wire skin = (cb>=12'sd77)&&(cb<=12'sd127)&&(cr>=12'sd133)&&(cr<=12'sd173);
  logic [23:0] col;
  always_comb col = skin ? 24'h00FF00 : {r8,g8,b8};

  (* ram_style = "block" *) logic [23:0] mem [0:DW*DH-1];
  always_ff @(posedge pclk)
    if (pixel_en && (pcnt[0]==1'b0) && (rcnt[0]==1'b0))
      mem[(rcnt>>1)*DW + (pcnt>>1)] <= col;

  logic [23:0] rd;
  always_ff @(posedge clk_disp) rd <= mem[(ry>>1)*DW + (rx>>1)];

  // 诊断：帧计数 + 是否见过像素
  logic [15:0] fcnt, f1, f2;
  logic        seen_p;   // 摄像头域：见过 pixel_en
  always_ff @(posedge pclk or negedge rst_n)
    if (!rst_n) begin fcnt<='0; seen_p<=1'b0; end
    else begin
      if (vsync & ~vsync_d) fcnt<=fcnt+1'b1;
      if (pixel_en)         seen_p<=1'b1;
    end
  logic s1, s2;
  always_ff @(posedge clk_disp or negedge rst_n)
    if (!rst_n) begin f1<='0; f2<='0; s1<=1'b0; s2<=1'b0; end
    else begin f1<=fcnt; f2<=f1; s1<=seen_p; s2<=s1; end

  always_comb begin
    if      (rx<48 && ry<48) rgb = {f2[15:12], f2[11:8], f2[7:4], 4'hF}; // 帧计数方块
    else if (!cfg_done)      rgb = 24'h800000;    // 红：配置未完成
    else if (!s2)            rgb = 24'h000080;    // 蓝：没有像素数据
    else                     rgb = rd;            // 正常预览
  end
endmodule