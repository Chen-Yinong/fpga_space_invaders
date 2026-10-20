// tb_render.sv — 渲染一帧并导出 frame.ppm（P6），用来看画面
`timescale 1ns/1ps
module tb_render;
  localparam int H_VISIBLE = 640;
  localparam int V_VISIBLE = 480;
  localparam int PSLOTS = 6, ESLOTS = 3;

  logic        clk = 0, rst_n = 0;
  logic [11:0] x, y;
  logic        hsync, vsync, video_active, frame_start;
  logic [23:0] rgb;

  // 游戏状态（本仿真固定，用于验证渲染）
  logic [8:0]  player_x = 9'd160;
  logic        player_visible = 1'b1;
  logic [PSLOTS-1:0]   pb_valid = 6'b000001;
  logic [PSLOTS*9-1:0] pb_x = '0;
  logic [PSLOTS*9-1:0] pb_y = '0;
  logic [ESLOTS-1:0]   eb_valid = 3'b001;
  logic [ESLOTS*9-1:0] eb_x = '0;
  logic [ESLOTS*9-1:0] eb_y = '0;
  logic [49:0] enemy_alive;
  logic [8:0]  enemy_x0 = 9'd40;
  logic [8:0]  enemy_y0 = 9'd40;
  logic [15:0] score = 16'd1234;
  logic [3:0]  lives = 4'd3;
  logic [2:0]  wave  = 3'd2;

  vga_timing u_timing (
    .clk_pix(clk), .rst_n(rst_n), .x(x), .y(y),
    .hsync(hsync), .vsync(vsync), .video_active(video_active), .frame_start(frame_start)
  );

  sprite_render #(.PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) u_render (
    .vid_x(x[9:0]), .vid_y(y[9:0]),
    .player_x(player_x), .player_visible(player_visible),
    .pb_valid(pb_valid), .pb_x(pb_x), .pb_y(pb_y),
    .eb_valid(eb_valid), .eb_x(eb_x), .eb_y(eb_y),
    .enemy_alive(enemy_alive), .enemy_x0(enemy_x0), .enemy_y0(enemy_y0),
    .score(score), .lives(lives), .wave(wave),
    .rgb(rgb)
  );

  always #20 clk = ~clk;   // 25MHz 像素时钟

  integer fd, cnt;
  initial begin
    pb_x[8:0] = 9'd160;
    pb_y[8:0] = 9'd140;
    eb_x[8:0] = 9'd200;
    eb_y[8:0] = 9'd100;
    enemy_alive = {50{1'b1}};
    enemy_alive[45] = 1'b0;   // 打掉几个，画面更真实
    enemy_alive[46] = 1'b0;
    enemy_alive[35] = 1'b0;

    fd  = $fopen("frame.ppm", "wb");
    $fwrite(fd, "P6\n%0d %0d\n255\n", H_VISIBLE, V_VISIBLE);
    cnt = 0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // 等到整帧边界
    @(posedge clk); while (!(x == 0 && y == 0)) @(posedge clk);
    @(posedge clk); while (!(x == 0 && y == 0)) @(posedge clk);

    // 采一整帧可见像素（光栅顺序）
    while (cnt < H_VISIBLE * V_VISIBLE) begin
      if (video_active) begin
        $fwrite(fd, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
        cnt = cnt + 1;
      end
      @(posedge clk);
    end

    $fclose(fd);
    $display("FRAME_DONE pixels=%0d", cnt);
    $finish;
  end
endmodule
