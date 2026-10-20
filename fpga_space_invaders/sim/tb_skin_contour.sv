// tb_skin_contour.sv — 验证 skin_calib + cam_frame_buf(背景差分 + 轮廓)
//
// 场景（对应现场）：
//   上半屏  ：暖白墙（不满足 Cr-Cb，颜色判据就该排除）
//   下半屏  ：木桌 —— 故意用【和手完全一样】的颜色，颜色判据绝对分不开
//   一只手  ：在画面里移动
//
// 验证目标：
//   1) 木桌虽然和手同色，但因为静止，被背景差分排除（墙面/桌面交界处不应有白轮廓）
//   2) 移动的手被正确描边
//   3) 肤色标定仍然正常（阈值 + 上屏 Cb/Cr 数值）
`timescale 1ns/1ps
module tb_skin_contour;

  logic pclk = 0, rst_n = 0;
  always #10 pclk = ~pclk;

  logic        vsync = 0, href = 0, pixel_en = 0, calib_btn = 0;
  logic [15:0] pixel = 0;

  localparam logic [15:0] HAND = {5'd28, 6'd45, 5'd18};   // RGB888 231,182,148 -> Cb≈102 Cr≈155 Y≈192
  localparam logic [15:0] WALL = {5'd29, 6'd57, 5'd26};   // 暖白：RGB888 239,231,214 -> Cr-Cb≈10
  // 木桌：同色系但更暗（RGB888 165,121,90 -> Cb≈105 Cr≈152 Y≈130）
  // 颜色判据分不开（Cr-Cb=47，和手一样），只能靠背景差分
  localparam logic [15:0] DESK = {5'd20, 6'd30, 5'd11};
  // 手背高光：RGB888 255,243,228 -> Cb≈119 Cr≈135（彩度低，最容易被判成"不是肤色"而打出洞）
  localparam logic [15:0] HILITE = {5'd31, 6'd60, 5'd28};

  int hand_x = 200;          // 当前帧手的左边界（每帧变化 -> 制造运动）

  // ---- 照抄 top_cam_game 的坐标计数 ----
  logic [11:0] cpx = 0, cpy = 0; logic href_d = 0, vsync_d = 0;
  always_ff @(posedge pclk or negedge rst_n)
    if (!rst_n) begin cpx<='0; cpy<='0; href_d<=1'b0; vsync_d<=1'b0; end
    else begin
      href_d<=href; vsync_d<=vsync;
      if (vsync & ~vsync_d)      begin cpx<='0; cpy<='0; end
      else if (href & ~href_d)   begin cpx<='0; cpy<=cpy+1'b1; end
      else if (pixel_en)         begin cpx<=cpx+1'b1; end
    end

  logic [7:0] r8, g8, b8; logic signed [11:0] cb, cr;
  rgb2ycrcb u_ycc (.pixel(pixel), .r8(r8), .g8(g8), .b8(b8), .cb(cb), .cr(cr));

  logic [7:0] cb_lo, cb_hi, cr_lo, cr_hi;
  logic calib_done, calib_busy;
  logic [1:0] calib_stat;
  logic [7:0] mon_cb, mon_cr;
  skin_calib u_cal (
    .pclk(pclk), .rst_n(rst_n), .pixel_en(pixel_en), .cb(cb), .cr(cr),
    .px(cpx), .py(cpy), .vsync(vsync), .calib_btn(calib_btn),
    .cb_lo(cb_lo), .cb_hi(cb_hi), .cr_lo(cr_lo), .cr_hi(cr_hi),
    .calib_done(calib_done), .calib_ok(), .calib_busy(calib_busy), .calib_stat(calib_stat),
    .mon_cb(mon_cb), .mon_cr(mon_cr)
  );

  // 肤色判定：与 top_cam_game 完全一致（区间 + 彩度 + 暖色）
  logic skin;
  wire [8:0] cbu = cb[8:0];
  wire [8:0] cru = cr[8:0];
  wire [8:0] dcb = (cbu >= 9'd128) ? (cbu - 9'd128) : (9'd128 - cbu);
  wire [8:0] dcr = (cru >= 9'd128) ? (cru - 9'd128) : (9'd128 - cru);
  wire       sat_ok  = (dcb + dcr) >= 10'd8;
  wire signed [12:0] cr_cb = cr - cb;
  wire       warm_ok = (cr_cb >= 13'sd14);
  assign skin = calib_done &&
                (cb >= $signed({4'b0000,cb_lo})) && (cb <= $signed({4'b0000,cb_hi})) &&
                (cr >= $signed({4'b0000,cr_lo})) && (cr <= $signed({4'b0000,cr_hi})) &&
                sat_ok && warm_ok;

  logic [17:0] raddr = 0; logic [23:0] rd; logic hand_pix;
  cam_frame_buf #(.DW(320), .DH(240), .INIT_FRAMES(6), .REINIT_FRAMES(2)) u_buf (
    .pclk(pclk), .rst_n(rst_n), .pixel_en(pixel_en), .pixel(pixel), .skin(skin),
    .href(href), .vsync(vsync), .clk_disp(pclk), .raddr(raddr),
    .fill_skin(1'b0), .freeze_bg(1'b0), .hand_pix(hand_pix), .rd(rd)
  );

  function automatic bit in_hand(input int x, input int y);
    return (x >= hand_x) && (x < hand_x + 120) && (y >= 120) && (y < 320);
  endfunction
  function automatic bit is_noise(input int x, input int y);
    return (((x * 7 + y * 13) % 211) == 0);
  endfunction
  // 手背高光块：位于手内部（离边界足够远），模拟受光面
  function automatic bit is_hilite(input int x, input int y);
    return (x >= hand_x + 40) && (x < hand_x + 70) && (y >= 180) && (y < 230);
  endfunction

  task automatic one_frame();
    @(negedge pclk) vsync <= 1'b1;
    repeat (4) @(negedge pclk);
    @(negedge pclk) vsync <= 1'b0;
    repeat (4) @(negedge pclk);
    for (int y = 0; y < 480; y++) begin
      @(negedge pclk) href <= 1'b1;
      for (int x = 0; x < 640; x++) begin
        @(negedge pclk);
        if      (in_hand(x,y) && is_hilite(x,y)) pixel <= HILITE;
        else if (in_hand(x,y) || is_noise(x,y))  pixel <= HAND;
        else if (y < 240)                        pixel <= WALL;
        else                                     pixel <= DESK;
        pixel_en <= 1'b1;
      end
      @(negedge pclk) pixel_en <= 1'b0;
      @(negedge pclk) href <= 1'b0;
      repeat (2) @(negedge pclk);
    end
  endtask

  task automatic read_px(input int sx, input int sy, output logic [23:0] v);
    @(negedge pclk) raddr <= 18'(sy*320 + sx);
    repeat (2) @(negedge pclk);
    v = rd;
  endtask

  task automatic dump_ppm(input string fname, input int W, input int H, input int step);
    int fd; logic [23:0] v;
    fd = $fopen(fname, "wb");
    if (fd == 0) begin $display("FAIL 打不开 %s", fname); return; end
    $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++) begin
        @(negedge pclk) raddr <= 18'((y*step)*320 + (x*step));
        repeat (2) @(negedge pclk);
        v = rd;
        $fwrite(fd, "%c%c%c", v[23:16], v[15:8], v[7:0]);
      end
    $fclose(fd);
    $display("TB   dump -> %s (%0dx%0d)", fname, W, H);
  endtask

  int errors = 0;
  logic [23:0] v;
  int white_cnt;

  initial begin
    repeat (4) @(negedge pclk) rst_n <= 1'b1;
    repeat (4) @(negedge pclk);

    // ---------- 阶段 1：没手，让背景学会墙和桌子 ----------
    hand_x = 900;                       // 手不在画面里
    for (int f = 0; f < 8; f++) one_frame();
    $display("TB   背景初始化完成（8 帧，手不在画面内）");

    // ---------- 阶段 2：手开始移动 ----------
    hand_x = 200; one_frame();
    hand_x = 260; one_frame();
    hand_x = 320; one_frame();
    repeat (20) @(negedge pclk);
    $display("TB   手移动 3 帧，当前手 x=%0d", hand_x);

    // 桌面/墙面交界处（y=240，sy≈120）：桌面和手同色，但它是静止背景，
    // 若背景差分生效，这里不应该出现白轮廓
    white_cnt = 0;
    for (int k = 118; k <= 122; k++) begin
      read_px(20, k, v);
      if (v === 24'hFFFFFF) white_cnt++;
    end
    if (white_cnt != 0) begin
      $display("FAIL 桌面/墙面交界处出现白轮廓 %0d 次 —— 静止木桌没被排除", white_cnt); errors++;
    end else $display("TB   静止木桌未被误判 OK（与手同色也不描边）");

    // 手的左边 sx≈160 附近应有白轮廓
    white_cnt = 0;
    for (int k = 155; k <= 172; k++) begin
      read_px(k, 150, v);
      if (v === 24'hFFFFFF) white_cnt++;
    end
    if (white_cnt == 0) begin $display("FAIL 移动的手没有白轮廓"); errors++; end
    else $display("TB   移动的手有白轮廓（命中 %0d 个像素）", white_cnt);

    // 手内部保留原色
    read_px(190, 150, v);
    if (v === 24'hFFFFFF) begin $display("FAIL 手内部不应是白的"); errors++; end
    else $display("TB   手内部保留原色 OK (%06h)", v);

    // 手背高光处（sy≈100, sx≈185）：低彩度区域不能被打成洞（否则轮廓会被切断）
    read_px(185, 100, v);
    if (v === 24'hFFFFFF) begin
      $display("FAIL 手背高光被打成洞（内部出现轮廓）"); errors++;
    end else $display("TB   手背高光未被挖洞 OK (%06h)", v);

    // 墙：不应被当成手
    read_px(20, 20, v);
    if (v === 24'hFFFFFF) begin $display("FAIL 墙被描边了"); errors++; end
    else $display("TB   暖白墙未被误判 OK (%06h)", v);

    // ---------- 肤色标定仍然正常 ----------
    @(negedge pclk) calib_btn <= 1'b1;
    hand_x = 280;                       // 手盖住标定框(280..360)
    for (int f = 0; f < 3; f++) one_frame();
    repeat (600) @(negedge pclk);
    $display("TB   标定: cb[%0d,%0d] cr[%0d,%0d] stat=%0d 上屏 Cb=%0d Cr=%0d",
             cb_lo, cb_hi, cr_lo, cr_hi, calib_stat, mon_cb, mon_cr);
    if (calib_stat !== 2'd3) begin $display("FAIL 标定应可用"); errors++; end
    if (mon_cb < 95 || mon_cb > 107) begin $display("FAIL 上屏 Cb 应≈102"); errors++; end
    if (mon_cr < 150 || mon_cr > 160) begin $display("FAIL 上屏 Cr 应≈155"); errors++; end
    @(negedge pclk) calib_btn <= 1'b0;

    dump_ppm("D:/fpga/fpga_space_invaders/fpga_space_invaders/sim/contour_320x240.ppm", 320, 240, 1);
    dump_ppm("D:/fpga/fpga_space_invaders/fpga_space_invaders/sim/contour_window.ppm",   160, 120, 2);

    if (errors == 0) $display("\n===== ALL PASS =====");
    else             $display("\n===== %0d FAIL =====", errors);
    $finish;
  end
endmodule
