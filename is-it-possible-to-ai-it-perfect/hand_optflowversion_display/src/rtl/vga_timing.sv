// vga_timing.sv — 标准 VGA 640x480@60 时序发生器（负极性同步）
`timescale 1ns/1ps
module vga_timing #(
  parameter int H_VISIBLE = 640,
  parameter int H_FRONT   = 16,
  parameter int H_SYNC    = 96,
  parameter int H_BACK    = 48,
  parameter int V_VISIBLE = 480,
  parameter int V_FRONT   = 10,
  parameter int V_SYNC    = 2,
  parameter int V_BACK    = 33
)(
  input  logic        clk_pix,      // 像素时钟 25.175MHz
  input  logic        rst_n,
  output logic [11:0] x,
  output logic [11:0] y,
  output logic        hsync,
  output logic        vsync,
  output logic        video_active, // 可见像素区
  output logic        frame_start   // 帧首（x=0,y=0）
);
  localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800
  localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

  logic [11:0] hcnt, vcnt;
  always_ff @(posedge clk_pix or negedge rst_n) begin
    if (!rst_n) begin
      hcnt <= '0; vcnt <= '0;
    end else if (hcnt == H_TOTAL-1) begin
      hcnt <= '0;
      vcnt <= (vcnt == V_TOTAL-1) ? '0 : vcnt + 1'b1;
    end else begin
      hcnt <= hcnt + 1'b1;
    end
  end

  assign x = hcnt;
  assign y = vcnt;
  assign hsync = ~((hcnt >= H_VISIBLE + H_FRONT) && (hcnt < H_VISIBLE + H_FRONT + H_SYNC));
  assign vsync = ~((vcnt >= V_VISIBLE + V_FRONT) && (vcnt < V_VISIBLE + V_FRONT + V_SYNC));
  assign video_active = (hcnt < H_VISIBLE) && (vcnt < V_VISIBLE);
  assign frame_start  = (hcnt == 0) && (vcnt == 0);
endmodule