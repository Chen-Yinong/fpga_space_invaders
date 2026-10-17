// cam_frame_buf.sv — 摄像头帧缓存（320x240 RGB888，双时钟）；肤色像素存绿色
`timescale 1ns/1ps
module cam_frame_buf #(
  parameter int DW = 320,
  parameter int DH = 240
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic [15:0] pixel,
  input  logic        skin,
  input  logic        href,
  input  logic        vsync,
  input  logic        clk_disp,
  input  logic [17:0] raddr,
  output logic [23:0] rd
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
  wire [23:0] col = skin ? 24'h00FF00 : {r8,g8,b8};

  (* ram_style="block" *) logic [23:0] mem [0:DW*DH-1];
  always_ff @(posedge pclk)
    if (pixel_en && (pcnt[0]==1'b0) && (rcnt[0]==1'b0))
      mem[(rcnt>>1)*DW + (pcnt>>1)] <= col;

  always_ff @(posedge clk_disp) rd <= mem[raddr];
endmodule