// skin_calib.sv — 肤色标定（算法照 scripts/square_demo.py）
//   按住 key: 每帧在 ROI 内统计 Cb/Cr 均值，滚动累计各帧均值的 min/max，
//             并实时把阈值刷成 [mean_min-12, mean_max+12] -> 轮廓随采样立即变化
//   松手:     停止累计，阈值定格
//   上电默认: 标准肤色区间 Cb 77..127 / Cr 133..173（不标定也能玩）
//
// 均值 = sum / npix，用"重复减法"实现：最多 255 次，每次 1 拍（~11us @24MHz），
// 帧间隔有几十毫秒，完全够用。这样**不要求 npix 是 2 的幂**，ROI 大小可以随便改。
//
// calib_stat 给你看标定到底卡在哪：
//   0 = 一帧都没采到（npix 或 vsync 有问题）
//   1 = 采到了，但各帧均值散布太宽（>64，手抖/光照在变）
//   2 = 采到了，但颜色不够暖（Cr 没有明显大于 Cb —— 大概采到的是灰/白/蓝的背景）
//   3 = 可用
`timescale 1ns/1ps
module skin_calib #(
  parameter int ROI_X0 = 280,      // 640x480 画面中心 80x80（缩小 ROI，保证框里主要是手）
  parameter int ROI_Y0 = 200,
  parameter int ROI_W  = 80,
  parameter int ROI_H  = 80,
  parameter int MARGIN = 24        // 放宽：颜色不再负责排除静止家具（那是背景差分的活）
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic signed [11:0] cb, cr,
  input  logic [11:0] px, py,
  input  logic        vsync,
  input  logic        calib_btn,     // 高 = 按住（已同步到 pclk）
  output logic [7:0]  cb_lo, cb_hi, cr_lo, cr_hi,
  output logic        calib_done,    // 1 = 有可用阈值（默认值也算可用）
  output logic        calib_ok,      // 1 = 现场标定成功（框变绿）
  output logic        calib_busy,    // 1 = 正在采样（按住中）
  output logic [1:0]  calib_stat,    // 见文件头说明
  output logic [7:0]  mon_cb,        // 最近一帧采到的 Cb 均值（上屏显示用）
  output logic [7:0]  mon_cr         // 最近一帧采到的 Cr 均值
);
  // 默认肤色：按 2026-10-17 实测（手 Cb=110 / Cr=158）并配合放宽的 MARGIN
  localparam logic [7:0] DEF_CB_LO = 8'd86;
  localparam logic [7:0] DEF_CB_HI = 8'd134;
  localparam logic [7:0] DEF_CR_LO = 8'd134;
  localparam logic [7:0] DEF_CR_HI = 8'd186;

  logic        vsync_d, btn_d;
  logic [31:0] cb_sum, cr_sum, npix;
  logic [7:0]  mn_cb, mx_cb, mn_cr, mx_cr;   // 各帧均值的 min/max
  logic        got_frame;

  // ---- 重复减法除法器 ----
  logic        div_busy;
  logic [31:0] rem_cb, rem_cr, npix_reg;
  logic [7:0]  mcnt_cb, mcnt_cr;             // 本帧均值（逐次减 1 的商）

  wire vs_rise = vsync & ~vsync_d;
  wire in_roi  = (px >= ROI_X0) && (px < ROI_X0 + ROI_W) &&
                 (py >= ROI_Y0) && (py < ROI_Y0 + ROI_H);

  // Cb/Cr 是 12 位有符号，但真实取值在 0..255；这里按低 8 位取用
  wire [7:0] cbn = cb[7:0];
  wire [7:0] crn = cr[7:0];

  // ---- 采样质量判据（只用于告诉用户，不阻止阈值生效）----
  wire range_ok = (mx_cb <= mn_cb + 9'd32) && (mx_cr <= mn_cr + 9'd32);
  wire [9:0] sum_cb = {2'b00,mn_cb} + {2'b00,mx_cb};
  wire [9:0] sum_cr = {2'b00,mn_cr} + {2'b00,mx_cr};
  wire warm_ok  = sum_cr > (sum_cb + 10'd30);

  assign calib_stat = !got_frame ? 2'd0 : (!range_ok ? 2'd1 : (!warm_ok ? 2'd2 : 2'd3));
  assign calib_ok   = (calib_stat == 2'd3);
  assign calib_done = 1'b1;            // 永远有可用阈值（默认值兜底）

  // 只要采到过一帧就直接用（阈值本来就是跟你的手学出来的）
  wire use_cal = got_frame;

  always_comb begin
    if (use_cal) begin
      cb_lo = (mn_cb > MARGIN)         ? (mn_cb - MARGIN) : 8'd0;
      cb_hi = (mx_cb < 8'd255-MARGIN)  ? (mx_cb + MARGIN) : 8'd255;
      cr_lo = (mn_cr > MARGIN)         ? (mn_cr - MARGIN) : 8'd0;
      cr_hi = (mx_cr < 8'd255-MARGIN)  ? (mx_cr + MARGIN) : 8'd255;
    end else begin
      cb_lo = DEF_CB_LO; cb_hi = DEF_CB_HI;
      cr_lo = DEF_CR_LO; cr_hi = DEF_CR_HI;
    end
  end

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      vsync_d    <= 1'b0;
      btn_d      <= 1'b0;
      cb_sum     <= '0;
      cr_sum     <= '0;
      npix       <= '0;
      mn_cb      <= 8'hFF;
      mx_cb      <= 8'h00;
      mn_cr      <= 8'hFF;
      mx_cr      <= 8'h00;
      got_frame  <= 1'b0;
      div_busy   <= 1'b0;
      rem_cb     <= '0;
      rem_cr     <= '0;
      npix_reg   <= '0;
      mcnt_cb    <= '0;
      mcnt_cr    <= '0;
      mon_cb     <= '0;
      mon_cr     <= '0;
      calib_busy <= 1'b0;
    end else begin
      vsync_d <= vsync;
      btn_d   <= calib_btn;
      calib_busy <= calib_btn;

      // 按下瞬间重新开始累计
      if (calib_btn & ~btn_d) begin
        mn_cb     <= 8'hFF;
        mx_cb     <= 8'h00;
        mn_cr     <= 8'hFF;
        mx_cr     <= 8'h00;
        got_frame <= 1'b0;
      end

      // ROI 内累加
      if (calib_btn && pixel_en && in_roi) begin
        cb_sum <= cb_sum + cbn;
        cr_sum <= cr_sum + crn;
        npix   <= npix + 1'b1;
      end

      if (vs_rise) begin
        // 帧末：启动均值计算
        if (calib_btn && (npix >= 32'd1024)) begin
          npix_reg <= npix;
          rem_cb   <= cb_sum;
          rem_cr   <= cr_sum;
          mcnt_cb  <= 8'd0;
          mcnt_cr  <= 8'd0;
          div_busy <= 1'b1;
        end else begin
          div_busy <= 1'b0;
        end
        cb_sum <= '0;
        cr_sum <= '0;
        npix   <= '0;
      end else if (div_busy) begin
        // 重复减法求均值：每拍从余数里减掉一个 npix
        if (rem_cb >= npix_reg) begin rem_cb  <= rem_cb - npix_reg; mcnt_cb <= mcnt_cb + 1'b1; end
        if (rem_cr >= npix_reg) begin rem_cr  <= rem_cr - npix_reg; mcnt_cr <= mcnt_cr + 1'b1; end
        if ((rem_cb < npix_reg) && (rem_cr < npix_reg)) begin
          div_busy <= 1'b0;
          mon_cb <= mcnt_cb;              // 上屏显示用
          mon_cr <= mcnt_cr;
          if (mcnt_cb < mn_cb) mn_cb <= mcnt_cb;
          if (mcnt_cb > mx_cb) mx_cb <= mcnt_cb;
          if (mcnt_cr < mn_cr) mn_cr <= mcnt_cr;
          if (mcnt_cr > mx_cr) mx_cr <= mcnt_cr;
          got_frame <= 1'b1;
        end
      end
    end
  end
endmodule
