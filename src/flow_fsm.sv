// flow_fsm.sv — 光流方向投票 + 漏桶积分器 + 显示标签
//
//   每个块矢量出来时，若能量足够且 |u| 超阈值，按符号投一票：
//     u<0 -> cnt_left++，u>0 -> cnt_right++，同时写显示标签 RAM。
//   每帧结束用票数判定本帧方向（要求单方向票数够多、且比对方多出 MAJORITY 票），
//   帧方向送入漏桶积分器：连续同向才点亮 LED，静止时向 0 漏电，
//   单帧/偶发抖动不会导致左右乱闪，且天然保留明确的静止态。
`timescale 1ns/1ps
module flow_fsm #(
  parameter int NBX     = 20,
  parameter int NBY     = 15,
  parameter int QF      = 16,
  parameter int TAG_SHIFT = 5,   // 显示块边长 = 2^TAG_SHIFT（全屏 32 / 画中画 8）
  // 单块可信度：|u| >= U_MIN（定点 Q16，单位：处理域像素/帧）且能量 >= E_MIN
  // 注：LK 对帧间位移存在低估，U_MIN 设小（0.125 像素/帧），主要靠方向一致性投票。
  parameter int U_MIN   = 8192,
  parameter int E_MIN   = 8000,
  // 帧方向判定
  parameter int CNT_MIN   = 2,   // 单方向至少几票
  parameter int MAJORITY  = 2,   // 优势方向至少多出的票数
  // 漏桶积分器
  parameter int TH_BUCKET  = 3,  // 连续几帧一致才点亮（漏桶阈值）
  parameter int BUCKET_MAX = 8   // 漏桶饱和值
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        flow_valid,
  input  logic signed [31:0] flow_u,
  input  logic signed [31:0] flow_v,
  input  logic [31:0] flow_energy,
  input  logic [4:0]  flow_bx,
  input  logic [3:0]  flow_by,
  input  logic        vsync,
  // 显示侧（clk_disp 域读标签）
  input  logic        clk_disp,
  input  logic [11:0] px,
  input  logic [11:0] py,
  output logic [1:0]  tag_out,
  // LED
  output logic        led_stop,
  output logic        led_left,
  output logic        led_right
);
  localparam int TAG_DEPTH = NBX * NBY;   // 300

  // =========================================================================
  // 1. 逐块投票 + 标签写 RAM
  // =========================================================================
  wire moving = (flow_energy >= E_MIN)
             && ((flow_u >= U_MIN) || (flow_u <= -U_MIN));
  wire [1:0] tag = moving ? ((flow_u < 0) ? 2'd1 : 2'd2) : 2'd0;
  wire [8:0] tag_waddr = ({5'd0, flow_by} * 9'd20) + {4'd0, flow_bx};
  wire [8:0] raddr_disp = ((py >> TAG_SHIFT) * 9'd20) + (px >> TAG_SHIFT);

  logic vsync_d;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) vsync_d <= 1'b0;
    else        vsync_d <= vsync;
  end
  wire frame_tick = vsync && !vsync_d;

  logic [8:0] cnt_left, cnt_right;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_left  <= 9'd0;
      cnt_right <= 9'd0;
    end else if (frame_tick) begin
      cnt_left  <= 9'd0;
      cnt_right <= 9'd0;
    end else if (flow_valid && moving) begin
      if (flow_u < 0)
        cnt_left  <= cnt_left + 1'b1;
      else
        cnt_right <= cnt_right + 1'b1;
    end
  end

  flow_tag_ram #(.DEPTH(TAG_DEPTH)) u_tag (
    .wclk (pclk),
    .we   (flow_valid),
    .waddr(tag_waddr),
    .wdata(tag),
    .rclk (clk_disp),
    .raddr(raddr_disp),
    .rdata(tag_out)
  );

  // =========================================================================
  // 2. 帧方向判定（frame_tick 拍读清零前的计数值）
  // =========================================================================
  wire [8:0] total = cnt_left + cnt_right;
  wire frame_left  = (cnt_left  >= CNT_MIN) && (cnt_left  >= cnt_right + MAJORITY);
  wire frame_right = (cnt_right >= CNT_MIN) && (cnt_right >= cnt_left  + MAJORITY);

  // =========================================================================
  // 3. 漏桶积分器 + LED 输出
  // =========================================================================
  logic signed [7:0] bucket;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      bucket <= 8'sd0;
    end else if (frame_tick) begin
      if (frame_left && !frame_right) begin
        if (bucket > -BUCKET_MAX)
          bucket <= bucket - 1'b1;
      end else if (frame_right && !frame_left) begin
        if (bucket < BUCKET_MAX)
          bucket <= bucket + 1'b1;
      end else begin
        // 静止或左右矛盾：向 0 漏电
        if (bucket > 0)
          bucket <= bucket - 1'b1;
        else if (bucket < 0)
          bucket <= bucket + 1'b1;
      end
    end
  end

  assign led_right = (bucket >= TH_BUCKET);
  assign led_left  = (bucket <= -TH_BUCKET);
  assign led_stop  = (!led_left) && (!led_right);
endmodule
