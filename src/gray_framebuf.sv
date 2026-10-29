// gray_framebuf.sv — 双缓冲灰度帧缓存（2 × DW*DH × 8bit）
//   vsync 上升沿翻转 ping-pong：偶数帧写 mem0 读 mem1，奇数帧反之。
//   读地址与写地址同拍给出（raddr 通常接 waddr），读数据 1 拍后有效。
`timescale 1ns/1ps
module gray_framebuf #(
  parameter int DW = 320,
  parameter int DH = 240,
  parameter int AW = 17
)(
  input  logic         pclk,
  input  logic         rst_n,
  input  logic         vsync,
  input  logic         wr_en,
  input  logic [AW-1:0] waddr,
  input  logic [7:0]   gray_in,
  input  logic [AW-1:0] raddr,
  output logic [7:0]   gray_out
);
  localparam int DEPTH = DW * DH;

  logic frame_sel;
  logic vsync_d;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      frame_sel <= 1'b0;
      vsync_d   <= 1'b0;
    end else begin
      vsync_d <= vsync;
      if (vsync && !vsync_d)
        frame_sel <= ~frame_sel;
    end
  end

  (* ram_style = "block" *) logic [7:0] mem0 [0:DEPTH-1];
  (* ram_style = "block" *) logic [7:0] mem1 [0:DEPTH-1];
  logic [7:0] rd0, rd1;

  // mem0：偶数帧写当前帧，奇数帧读上一帧（单端口分时）
  always_ff @(posedge pclk) begin
    if (frame_sel == 1'b0) begin
      if (wr_en)
        mem0[waddr] <= gray_in;
    end else begin
      rd0 <= rst_n ? mem0[raddr] : 8'd0;
    end
  end

  // mem1：奇数帧写当前帧，偶数帧读上一帧（单端口分时）
  always_ff @(posedge pclk) begin
    if (frame_sel == 1'b1) begin
      if (wr_en)
        mem1[waddr] <= gray_in;
    end else begin
      rd1 <= rst_n ? mem1[raddr] : 8'd0;
    end
  end

  assign gray_out = (frame_sel == 1'b0) ? rd1 : rd0;
endmodule
