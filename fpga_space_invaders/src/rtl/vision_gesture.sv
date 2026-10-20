// vision_gesture.sv — 手势 -> 左/右/停（流式，无帧缓存）
// 输入 skin（已按标定阈值判定），逐帧累加 x 和像素数，帧末比较质心位移
`timescale 1ns/1ps
module vision_gesture #(
  parameter int K_PIX   = 6,
  parameter int MIN_PIX = 2000
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic        skin,
  input  logic        href,
  input  logic        vsync,
  output logic [1:0]  move_cmd
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

  logic [31:0] xsum, cnt, xsum_prev, cnt_prev;
  // 质心位移判据：|cx_cur - cx_prev| > K_PIX
  //   <=> |xsum_cur*cnt_prev - xsum_prev*cnt_cur| > K_PIX * cnt_cur * cnt_prev
  // 用 64 位交叉相乘，避免除法，也不受“手张开/握拳导致像素数变化”的干扰。
  logic [63:0] t1, t2, t3, diff;
  always_comb begin
    t1   = {32'b0, xsum} * {32'b0, cnt_prev};
    t2   = {32'b0, xsum_prev} * {32'b0, cnt};
    t3   = {32'b0, cnt} * {32'b0, cnt_prev} * K_PIX;
    diff = (t1 >= t2) ? (t1 - t2) : (t2 - t1);
  end
  wire frame_end = vsync & ~vsync_d;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin xsum<='0; cnt<='0; xsum_prev<='0; cnt_prev<='0; move_cmd<=2'b00; end
    else begin
      if (pixel_en && skin) begin xsum<=xsum+pcnt; cnt<=cnt+1'b1; end
      if (frame_end) begin
        xsum_prev <= xsum;
        cnt_prev  <= cnt;
        if (cnt >= MIN_PIX && cnt_prev >= MIN_PIX) begin
          if (diff > t3) move_cmd <= (t1 >= t2) ? 2'b10 : 2'b01;
          else           move_cmd <= 2'b00;
        end else move_cmd <= 2'b00;
        xsum <= '0; cnt <= '0;
      end
    end
  end
endmodule
