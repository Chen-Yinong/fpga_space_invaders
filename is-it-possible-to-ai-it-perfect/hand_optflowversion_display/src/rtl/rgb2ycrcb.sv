// rgb2ycrcb.sv — RGB565 -> RGB888 + YCbCr（组合）
`timescale 1ns/1ps
module rgb2ycrcb (
  input  logic [15:0] pixel,
  output logic [7:0]  r8, g8, b8,
  output logic signed [11:0] cb, cr
);
  logic [4:0] r5; logic [5:0] g6; logic [4:0] b5;
  assign r5=pixel[15:11]; assign g6=pixel[10:5]; assign b5=pixel[4:0];
  assign r8={r5,r5[4:2]}; assign g8={g6,g6[5:4]}; assign b8={b5,b5[4:2]};
  always_comb begin
    cb = 12'sd128 + (( -43*$signed({1'b0,r8}) - 85*$signed({1'b0,g8}) + 128*$signed({1'b0,b8}) ) >>> 8);
    cr = 12'sd128 + (( 128*$signed({1'b0,r8}) - 107*$signed({1'b0,g8}) -  21*$signed({1'b0,b8}) ) >>> 8);
  end
endmodule