// rgb2gray.sv — RGB565 -> 8bit 灰度（BT.601 整数近似）
//   Y = (77R + 150G + 29B) >> 8
`timescale 1ns/1ps
module rgb2gray (
  input  logic [15:0] pixel,
  output logic [7:0]  gray
);
  logic [4:0] r5;
  logic [5:0] g6;
  logic [4:0] b5;
  logic [7:0] r8, g8, b8;

  assign r5 = pixel[15:11];
  assign g6 = pixel[10:5];
  assign b5 = pixel[4:0];
  assign r8 = {r5, r5[4:2]};
  assign g8 = {g6, g6[5:4]};
  assign b8 = {b5, b5[4:2]};

  assign gray = (16'(77 * r8) + 16'(150 * g8) + 16'(29 * b8)) >> 8;
endmodule
