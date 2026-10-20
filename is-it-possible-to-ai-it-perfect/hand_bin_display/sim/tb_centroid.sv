// tb_centroid.sv — 验证质心与帧间位移 dx（适配 28 拍除法状态机版本）
`timescale 1ns/1ps
module tb_centroid;
  logic        pclk = 0, rst_n = 0;
  logic        pixel_en = 0, skin = 0, href = 0, vsync = 0;
  logic        valid;
  logic [9:0]  cx;
  logic [8:0]  cy;
  logic signed [10:0] dx;

  centroid_calc #(.MIN_PIX(50)) dut (.*);

  always #20 pclk = ~pclk;

  integer errors = 0;

  // 发一帧：列 lo..hi 为 skin，帧末等除法状态机跑完
  task automatic frame(input int lo, input int hi);
    @(negedge pclk); href <= 1'b1;
    for (int i=0; i<400; i++) begin
      @(negedge pclk); pixel_en<=1'b1; skin<=((i>=lo)&&(i<=hi));
    end
    @(negedge pclk); pixel_en<=1'b0; skin<=1'b0; href<=1'b0;
    @(negedge pclk); vsync<=1'b1;
    @(negedge pclk); vsync<=1'b0;
    repeat (40) @(negedge pclk);   // 等 28 拍除法 + ST_DONE
  endtask

  initial begin
    repeat (4) @(negedge pclk); rst_n = 1'b1;
    repeat (4) @(negedge pclk);

    frame(100, 199);   // 帧1：cx_raw=149
    if (valid !== 1'b1) begin $display("[FAIL] f1 valid=%b", valid); errors++; end
    else                $display("[PASS] f1 valid=1");
    if (cx !== 10'd149) begin $display("[FAIL] f1 cx=%0d exp=149", cx); errors++; end
    else                $display("[PASS] f1 cx=149");
    if (dx !== 11'sd0)  begin $display("[FAIL] f1 dx=%0d exp=0", dx); errors++; end
    else                $display("[PASS] f1 dx=0");

    frame(200, 299);   // 帧2：cx_raw=249，dx = 249-149 = 100
    if (dx !== 11'sd100) begin $display("[FAIL] f2 dx=%0d exp=100", dx); errors++; end
    else                 $display("[PASS] f2 dx=100");

    frame(120, 219);   // 帧3：cx_raw=169，dx = 169-249 = -80
    if (dx !== -11'sd80) begin $display("[FAIL] f3 dx=%0d exp=-80", dx); errors++; end
    else                 $display("[PASS] f3 dx=-80");

    if (errors == 0) $display("\n==== TB_CENTROID ALL PASS ====");
    else             $display("\n==== TB_CENTROID FAILED: %0d ====", errors);
    $finish;
  end

  initial begin
    #4000000; $display("TIMEOUT"); $finish;
  end
endmodule
