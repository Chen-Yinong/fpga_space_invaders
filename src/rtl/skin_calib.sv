// skin_calib.sv — 肤色标定：按键触发，在画面中心 ROI 采样 Cb/Cr 范围
// 采样 CAL_FRAMES 帧后，阈值 = [min-8, max+8]（带兜底：没采到就保持默认）
`timescale 1ns/1ps
module skin_calib #(
  parameter int ROI_X0 = 240,
  parameter int ROI_X1 = 400,
  parameter int ROI_Y0 = 160,
  parameter int ROI_Y1 = 320,
  parameter int CAL_FRAMES = 45
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
  wire [7:0] cbm = (cbmin + cbmax) >> 1;
  wire [7:0] crm = (crmin + crmax) >> 1;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      st<=S_IDLE; vsync_d<=1'b0; btn_d<=1'b0;
      cbmin<=8'hFF; cbmax<=8'h00; crmin<=8'hFF; crmax<=8'h00;
      // 上电默认“无肤色数据”：空区间，未采样前什么都不算皮肤
      cb_lo<=8'd255; cb_hi<=8'd0; cr_lo<=8'd255; cr_hi<=8'd0;
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
            // 合理性检查：采样中点必须“像肤色”，否则拒绝（框保持红，提示重采）
            if ((cbmax >= cbmin) && (crmax >= crmin) &&
                (cbm >= 8'd60) && (cbm <= 8'd150) &&
                (crm >= 8'd110) && (crm <= 8'd200)) begin
              cb_lo <= (cbm > 8'd12)  ? (cbm - 8'd12) : 8'd0;
              cb_hi <= (cbm < 8'd243) ? (cbm + 8'd12) : 8'd255;
              cr_lo <= (crm > 8'd12)  ? (crm - 8'd12) : 8'd0;
              cr_hi <= (crm < 8'd243) ? (crm + 8'd12) : 8'd255;
              calib_done <= 1'b1;
            end else begin
              calib_done <= 1'b0;   // 采样不像肤色 -> 拒绝
            end
            st<=S_DONE; calib_busy<=1'b0;
          end else fcnt <= fcnt + 8'd1;
        end
      end
    end
  end
endmodule