// tb_dyn_render.sv — 动态渲染：跑游戏 + 周期性点射(脉冲>1个tick)，连拍 9 帧
`timescale 1ns/1ps
module tb_dyn_render;
  localparam int HW = 640, VH = 480;

  logic clk_sys = 0, clk_pix = 0, rst_n = 0;
  logic btn_left = 0, btn_right = 0, btn_start = 0, btn_fire = 0;
  logic [23:0] vga_rgb;
  logic vga_hsync, vga_vsync, vga_de;

  top_button_game #(.TICK_DIV(166667), .MOVE_PERIOD(10), .DEB_CNT(10)) dut (
    .clk_sys(clk_sys), .clk_pix(clk_pix), .rst_n(rst_n),
    .btn_left_raw(btn_left), .btn_right_raw(btn_right),
    .btn_start_raw(btn_start),
    .vga_rgb(vga_rgb), .vga_hsync(vga_hsync), .vga_vsync(vga_vsync), .vga_de(vga_de)
  );

  always #5  clk_sys = ~clk_sys;   // 100 MHz
  always #20 clk_pix = ~clk_pix;   // 25 MHz

  logic [11:0] vx, vy;
  assign vx = dut.px;
  assign vy = dut.py;

  integer gtotal = 0;
  always @(posedge clk_pix) if (vga_de && vga_rgb == 24'hFFCA62) gtotal = gtotal + 1;

  // 周期性点射：5ms 低 + 3ms 高（脉冲 3ms > tick 1.67ms，保证被采到）
  initial forever begin
    #5_000_000; btn_fire = 1'b1;
    #3_000_000; btn_fire = 1'b0;
  end

  task automatic capture(input int k);
    integer fd; int c; int amb;
    fd = $fopen($sformatf("frame_%0d.ppm", k), "wb");
    $fwrite(fd, "P6\n%0d %0d\n255\n", HW, VH);
    amb = 0; c = 0;
    @(posedge clk_pix);
    while (!(vx == 0 && vy == 0)) @(posedge clk_pix);
    while (c < HW*VH) begin
      if (vga_de) begin
        if (vga_rgb == 24'hFFCA62) amb = amb + 1;
        $fwrite(fd, "%c%c%c", vga_rgb[23:16], vga_rgb[15:8], vga_rgb[7:0]);
        c = c + 1;
      end
      @(posedge clk_pix);
    end
    $fclose(fd);
    $display("frame_%0d: amber=%0d player_x=%0d bvalid=%0d", k, amb, dut.u_game.player_x, dut.u_game.pb_valid);
  endtask

  initial begin
    rst_n = 1'b0;
    repeat (20) @(negedge clk_sys);
    rst_n = 1'b1;
    repeat (20) @(negedge clk_sys);

    btn_start = 1'b1; #5_000_000; btn_start = 1'b0;
    #1_000_000;

    for (int k = 0; k < 9; k++) begin
      if (k >= 1 && k <= 3) begin btn_left = 1'b1; btn_right = 1'b0; end
      else if (k >= 5 && k <= 7) begin btn_left = 1'b0; btn_right = 1'b1; end
      else begin btn_left = 1'b0; btn_right = 1'b0; end
      capture(k);
    end

    $display("TOTAL amber cycles = %0d", gtotal);
    $display("ALL FRAMES DONE");
    $finish;
  end
endmodule