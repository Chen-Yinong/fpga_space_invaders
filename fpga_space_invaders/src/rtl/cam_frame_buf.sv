// cam_frame_buf.sv — 摄像头帧缓存 + 背景差分 + 肤色轮廓（320x240 抽点域，双时钟）
//
// 判决链：
//   Y    = (77R + 150G + 29B) >> 8            亮度
//   fg   = |Y - bg| > 16                      和背景差得远 = 有东西挡在前面
//   hand = skin & fg                          既像肤色、又不是静止背景
//   → 腐蚀/表决 → 边界 → 加粗 → 写帧缓存
//
// 背景模型（关键设计，见 docs/camera_calibration_log.md）：
//   * 上电前 INIT_FRAMES 帧：bg <= Y（把所有静止物学进背景，无论什么颜色）
//   * 之后只在「非肤色 且 |Y-bg| 小」时慢速跟随：bg += (Y-bg)>>6（约 2 秒）
//     —— 手永远学不进背景（它是肤色），所以停住多久都不会被吸收
//     —— 墙面/桌面这类静止背景会跟随，所以换场地不用重调阈值
//   * 场景切换检测：一帧内前景像素 > 60% 就强制重建 4 帧（挪摄像头/开关灯后 1~2 帧恢复）
//   * 标定期间冻结背景更新（freeze_bg=1），否则框里的手会被吸收掉
`timescale 1ns/1ps
module cam_frame_buf #(
  parameter int DW = 320,
  parameter int DH = 240,
  parameter int INIT_FRAMES = 40,      // 上电初始化帧数（约 1.3 s @30fps）
  parameter int REINIT_FRAMES = 4,     // 场景切换后强制重建帧数
  parameter int FG_MOVE_TH   = 16,     // 前景判定的亮度差阈值
  parameter int FG_RATIO_PCT = 60      // 前景占比超过这个百分比 -> 判为场景切换
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic [15:0] pixel,
  input  logic        skin,          // 肤色判定（来自 rgb2ycrcb + 阈值）
  input  logic        href,
  input  logic        vsync,
  input  logic        clk_disp,
  input  logic [17:0] raddr,
  input  logic        fill_skin,     // 1 = 标定态：hand 区域实心涂绿
  input  logic        freeze_bg,     // 1 = 冻结背景更新（标定中）
  output logic        hand_pix,      // 全分辨率：当前像素是否属于"手"（给手势模块用）
  output logic [23:0] rd
);
  // ---------------- 像素 / 行 计数 ----------------
  logic [11:0] pcnt, rcnt; logic href_d, vsync_d;
  always_ff @(posedge pclk or negedge rst_n)
    if (!rst_n) begin pcnt<='0; rcnt<='0; href_d<=1'b0; vsync_d<=1'b0; end
    else begin
      href_d<=href; vsync_d<=vsync;
      if (vsync & ~vsync_d)    begin pcnt<='0; rcnt<='0; end
      else if (href & ~href_d) begin pcnt<='0; rcnt<=rcnt+1'b1; end
      else if (pixel_en)       begin pcnt<=pcnt+1'b1; end
    end

  // ---------------- RGB565 -> RGB888 / 亮度 ----------------
  logic [4:0] r5; logic [5:0] g6; logic [4:0] b5;
  logic [7:0] r8, g8, b8;
  assign r5=pixel[15:11]; assign g6=pixel[10:5]; assign b5=pixel[4:0];
  assign r8={r5,r5[4:2]}; assign g8={g6,g6[5:4]}; assign b8={b5,b5[4:2]};
  wire [23:0] col = {r8,g8,b8};
  wire [15:0] y_sum = 16'd77*r8 + 16'd150*g8 + 16'd29*b8;   // <= 65280
  wire [7:0]  y8    = y_sum[15:8];

  // ---------------- 抽点域坐标 ----------------
  wire        samp = pixel_en && (pcnt[0]==1'b0) && (rcnt[0]==1'b0);
  wire [8:0]  sx   = pcnt[9:1];
  wire [8:0]  sy   = rcnt[9:1];
  wire [16:0] idx  = sy*DW + sx;

  // ---------------- 打一拍（BRAM 读延迟 1 拍）----------------
  logic        samp1; logic [8:0] sx1, sy1; logic skin1;
  logic [23:0] col1;  logic [7:0] y1; logic [16:0] idx1; logic [7:0] bg_r;

  (* ram_style="block" *) logic [7:0] bg_mem [0:DW*DH-1];    // 320x240x8 = 17 个 BRAM36

  always_ff @(posedge pclk) begin
    samp1 <= samp;
    if (samp) begin
      sx1<=sx; sy1<=sy; skin1<=skin; col1<=col; y1<=y8; idx1<=idx;
    end
  end
  // ---------------- 前景判定 + 背景更新 ----------------
  wire [8:0] dy_u = (y1 >= bg_r) ? ({1'b0,y1} - {1'b0,bg_r}) : ({1'b0,bg_r} - {1'b0,y1});
  wire       fg   = (dy_u > FG_MOVE_TH[8:0]);
  wire       hand = skin1 & fg;

  logic [5:0]  init_cnt;      // 上电初始化剩余帧
  logic [2:0]  reinit_cnt;    // 场景切换后强制重建剩余帧
  logic [16:0] fg_cnt;        // 本帧前景像素计数
  logic [16:0] fg_limit;

  wire learn   = (init_cnt != 6'd0) | (reinit_cnt != 3'd0);
  wire upd_ok  = !freeze_bg & (learn | (!skin1 & (dy_u <= FG_MOVE_TH[8:0])));
  wire [8:0] step = dy_u >> 6;                                  // 0..3，约 2 秒跟随
  wire [7:0] bg_next = learn ? y1
                     : ((y1 >= bg_r) ? (bg_r + step[7:0]) : (bg_r - step[7:0]));

  // 背景存储的读口和写口必须放在同一个时钟块里，Vivado 才认成简单双口 BRAM
  always_ff @(posedge pclk) begin
    if (samp)            bg_r <= bg_mem[idx];              // 读：当前采样点
    if (samp1 && upd_ok) bg_mem[idx1] <= bg_next;          // 写：上一个采样点（错开一拍，无同址冲突）
  end

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      init_cnt  <= INIT_FRAMES[5:0];
      reinit_cnt<= 3'd0;
      fg_cnt    <= '0;
      fg_limit  <= (DW*DH/100)*FG_RATIO_PCT;
    end else begin
      // 前景像素计数
      if (samp1 && fg) fg_cnt <= fg_cnt + 1'b1;

      // 帧末
      if (vsync & ~vsync_d) begin
        fg_cnt <= '0;
        if (init_cnt != 6'd0)       init_cnt <= init_cnt - 1'b1;
        else if (fg_cnt > fg_limit) reinit_cnt <= REINIT_FRAMES[2:0];   // 场景变了
        else if (reinit_cnt != 3'd0) reinit_cnt <= reinit_cnt - 1'b1;
      end
    end
  end

  // 给手势模块用：全分辨率（fg 保持到下一个抽点）
  logic fg_hold;
  always_ff @(posedge pclk) if (samp1) fg_hold <= fg;
  assign hand_pix = skin & fg_hold;

  // ---------------- 轮廓（在 hand 掩膜上做）----------------
  wire        bank  = sy1[0];
  wire        wr_ok = samp1 && (sy1 < DH[8:0]);
  wire [16:0] idx_w = sy1*DW + sx1;

  logic raw_lb0 [0:319];
  logic raw_lb1 [0:319];
  logic cln_lb0 [0:319];
  logic cln_lb1 [0:319];
  logic e_lb0   [0:319];
  logic e_lb1   [0:319];

  wire raw_up = bank ? raw_lb0[sx1] : raw_lb1[sx1];
  wire cln_up = bank ? cln_lb0[sx1] : cln_lb1[sx1];
  wire e_up   = bank ? e_lb0[sx1]   : e_lb1[sx1];

  logic hand_d, cln_d, e_d1, e_d2;
  wire cln     = (hand & hand_d) | (hand & raw_up) | (hand_d & raw_up);   // 2/3 多数表决
  wire is_edge = (cln ^ cln_d) | (cln ^ cln_up);
  wire e_h     = is_edge | e_d1 | e_d2;      // 水平加粗到 3
  wire e_hw    = e_h      | e_up;            // 垂直加粗到 2

  always_ff @(posedge pclk) begin
    if (samp1) begin
      hand_d <= hand;
      cln_d  <= cln;
      e_d1   <= is_edge;
      e_d2   <= e_d1;
      if (bank) begin raw_lb1[sx1] <= hand; cln_lb1[sx1] <= cln; e_lb1[sx1] <= e_h; end
      else      begin raw_lb0[sx1] <= hand; cln_lb0[sx1] <= cln; e_lb0[sx1] <= e_h; end
    end
  end

  wire [23:0] shown = e_hw ? 24'hFFFFFF
                    : ((fill_skin & cln) ? 24'h00C800 : col1);

  (* ram_style="block" *) logic [23:0] mem [0:DW*DH-1];
  always_ff @(posedge pclk)
    if (wr_ok)
      mem[idx_w] <= shown;

  always_ff @(posedge clk_disp) rd <= mem[raddr];
endmodule
