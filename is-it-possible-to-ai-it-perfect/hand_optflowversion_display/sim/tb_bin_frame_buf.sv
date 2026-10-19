// tb_bin_frame_buf.sv — 验证 1bit 帧缓存读写
`timescale 1ns/1ps
module tb_bin_frame_buf;
  logic        pclk = 0, clk_disp = 0, rst_n = 0;
  logic        pixel_en = 0, skin = 0, href = 0, vsync = 0;
  logic [8:0]  rdx = 0;
  logic [7:0]  rdy = 0;
  logic        bin_out;

  bin_frame_buf dut (.*);

  always #20 pclk = ~pclk;        // 写侧 ~25MHz
  always #19 clk_disp = ~clk_disp; // 读侧略不同频，模拟异步

  integer errors = 0;

  // 发一行像素：negedge 设置，posedge 被 DUT 采样
  task automatic row(input int n, input int skin_idx);
    @(negedge pclk); href <= 1'b1;
    for (int i=0; i<n; i++) begin
      @(negedge pclk); pixel_en<=1'b1; skin<=(i==skin_idx);
    end
    @(negedge pclk); pixel_en<=1'b0; skin<=1'b0; href<=1'b0;
  endtask

  initial begin
    repeat (4) @(negedge pclk); rst_n = 1'b1;
    repeat (4) @(negedge pclk);

    row(20, -1);   // 第一行：rcnt=1（奇数行，不抽点）
    row(20, 10);   // 第二行：rcnt=2（偶数行）；i=0 -> sx=0 写 0，i=10 -> sx=5 写 1

    // 帧结束
    @(negedge pclk); vsync<=1'b1;
    @(negedge pclk); vsync<=1'b0;

    // 读回写过的 skin 点 (sy=1, sx=5)
    repeat (8) @(negedge clk_disp);
    rdx <= 9'd5; rdy <= 8'd1;
    repeat (3) @(negedge clk_disp);
    if (bin_out !== 1'b1) begin $display("[FAIL] expect bin_out=1, got %b", bin_out); errors++; end
    else                  $display("[PASS] read back skin bit");

    // 读回写过的背景点 (sy=1, sx=0)
    rdx <= 9'd0; rdy <= 8'd1;
    repeat (3) @(negedge clk_disp);
    if (bin_out !== 1'b0) begin $display("[FAIL] expect bin_out=0, got %b", bin_out); errors++; end
    else                  $display("[PASS] read back background bit");

    if (errors == 0) $display("\n==== TB_BIN_FRAME ALL PASS ====");
    else             $display("\n==== TB_BIN_FRAME FAILED: %0d ====", errors);
    $finish;
  end

  initial begin
    #2000000; $display("TIMEOUT"); $finish;
  end
endmodule
