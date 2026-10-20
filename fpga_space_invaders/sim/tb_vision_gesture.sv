// tb_vision_gesture.sv — 验证质心位移判据
// 重点：手张开/握拳（肤色像素数变化）但质心不动时，不应误判方向。
`timescale 1ns/1ps
module tb_vision_gesture;
  logic        pclk = 0, rst_n = 0;
  logic        pixel_en = 0, skin = 0, href = 0, vsync = 0;
  logic [1:0]  move_cmd;

  vision_gesture #(.K_PIX(6), .MIN_PIX(50)) dut (.*);

  always #20 pclk = ~pclk;   // ~25MHz

  // 模拟一帧：先发 n_nonskin 个非肤色像素，再发 n_skin 个肤色像素，最后 vsync 帧结束
  task automatic frame(input int n_nonskin, input int n_skin);
    @(posedge pclk); href <= 1'b1;                      // 行开始
    for (int i=0; i<n_nonskin; i++) begin @(posedge pclk); pixel_en<=1'b1; skin<=1'b0; end
    for (int i=0; i<n_skin;    i++) begin @(posedge pclk); pixel_en<=1'b1; skin<=1'b1; end
    @(posedge pclk); pixel_en<=1'b0; skin<=1'b0; href<=1'b0;
    @(posedge pclk); vsync<=1'b1;                        // 帧结束
    @(posedge pclk); vsync<=1'b0;
  endtask

  integer errors = 0;
  task automatic check(input logic [1:0] exp, input string msg);
    @(posedge pclk);   // 等判定结果稳定
    if (move_cmd !== exp) begin
      $display("[FAIL] %s  exp=%b got=%b", msg, exp, move_cmd);
      errors = errors + 1;
    end else begin
      $display("[PASS] %s  cmd=%b", msg, move_cmd);
    end
  endtask

  initial begin
    repeat (4) @(negedge pclk); rst_n = 1'b1;
    repeat (4) @(negedge pclk);

    frame(50, 100);   // 帧1：列 50..149，质心 99.5，cnt=100（首帧，不判定）
    frame(0, 200);    // 帧2：列 0..199，质心 99.5，cnt=200（质心不变、大小翻倍）
    check(2'b00, "same centroid + size change -> no move");

    frame(60, 100);   // 帧3：列 60..159，质心 109.5（右移 10）
    check(2'b10, "centroid right 10 -> move right");

    frame(40, 100);   // 帧4：列 40..139，质心 89.5（左移 20）
    check(2'b01, "centroid left 20 -> move left");

    if (errors == 0) $display("\n==== TB_VISION ALL PASS ====");
    else             $display("\n==== TB_VISION FAILED: %0d ====", errors);
    $finish;
  end

  initial begin
    #2000000;
    $display("TIMEOUT");
    $finish;
  end
endmodule
