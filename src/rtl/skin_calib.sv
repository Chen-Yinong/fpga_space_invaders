// skin_calib.sv — 肤色标定：按键触发，在画面中心 ROI 采样 Cb/Cr 范围
// 采样 CAL_FRAMES 帧后，阈值 = [min-8, max+8]（带兜底：没采到就保持默认）
`timescale 1ns/1ps
module skin_calib #(
  parameter int ROI_X0 = 260,
  parameter int ROI_X1 = 380,
  parameter int ROI_Y0 = 180,
  parameter int ROI_Y1 = 300,
  parameter int CAL_FRAMES = 30
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic signed [11:0] cb, cr,
  input  logic [11:0] px, py,
  input  logic        vsync,
  input  logic        calib_btn,     // 已同步到 pclk 的电平（高=按下）
  output logic [7:0]  cb_lo, cb_hi, cr_lo, cr_hi,
  output logic        calib_done,
  output logic        calib_busy
);
  localparam logic [1:0] S_IDLE=2'd0, S_SAMP=2'd1, S_DONE=2'd2;
  logic [1:0]  st;
  logic        vsync_d, btn_d;
  logic [7:0]  cbmin, cbmax, crmin, crmax;
  logic [7:0]  fcnt;
  wire in_roi  = (px >= ROI_X0) && (px < ROI_X1) && (py >= ROI_Y0) && (py < ROI_Y1);
  wire vs_rise = vsync & ~vsync_d;
  wire btn_rise= calib_btn & ~btn_d;
  wire [7:0] cbn = cb[7:0];   // 采样时用低 8 位（Cb/Cr 本身 0..255）
  wire [7:0] crn = cr[7:0];

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      st<=S_IDLE; vsync_d<=1'b0; btn_d<=1'b0;
      cbmin<=8'hFF; cbmax<=8'h00; crmin<=8'hFF; crmax<=8'h00;
      cb_lo<=8'd77; cb_hi<=8'd127; cr_lo<=8'd133; cr_hi<=8'd173;
      calib_done<=1'b0; calib_busy<=1'b0; fcnt<=8'd0;
    end else begin
      vsync_d <= vsync; btn_d <= calib_btn;

      if (btn_rise) begin
        st<=S_SAMP; fcnt<=8'd0;
        cbmin<=8'hFF; cbmax<=8'h00; crmin<=8'hFF; crmax<=8'h00;
        calib_done<=1'b0; calib_busy<=1'b1;
      end else if (st==S_SAMP) begin
        if (pixel_en && in_roi) begin
          if (cbn < cbmin) cbmin <= cbn;
          if (cbn > cbmax) cbmax <= cbn;
          if (crn < crmin) crmin <= crn;
          if (crn > crmax) crmax <= crn;
        end
        if (vs_rise) begin
          if (fcnt >= CAL_FRAMES-1) begin
            if ((cbmax >= cbmin) && (crmax >= crmin)) begin
              // 用范围中点 ±12（窄而稳，避免把背景算进皮肤）
              cb_lo <= (((cbmin + cbmax) >> 1) > 8'd12)  ? (((cbmin + cbmax) >> 1) - 8'd12) : 8'd0;
              cb_hi <= (((cbmin + cbmax) >> 1) < 8'd243) ? (((cbmin + cbmax) >> 1) + 8'd12) : 8'd255;
              cr_lo <= (((crmin + crmax) >> 1) > 8'd12)  ? (((crmin + crmax) >> 1) - 8'd12) : 8'd0;
              cr_hi <= (((crmin + crmax) >> 1) < 8'd243) ? (((crmin + crmax) >> 1) + 8'd12) : 8'd255;
            end
            st<=S_DONE; calib_done<=1'b1; calib_busy<=1'b0;
          end else fcnt <= fcnt + 8'd1;
        end
      end
    end
  end
endmodule