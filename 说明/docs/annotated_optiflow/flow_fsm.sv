// ============================================================================
// flow_fsm.sv —— 逐行注释版（原文件 122 行）★ 从"每块的运动"到"手势方向"
// 三步：
//   1) 逐块投票：这 300 个块里，有多少块在往左、多少在往右（同时写显示标签）
//   2) 每帧结算：左票数够多且明显多于右 → 本帧判为"左"
//   3) 漏桶积分：连续几帧同向才真正输出，静下来会自动"漏电"回中立态
// 为什么要漏桶：单帧误判很常见，直接输出会左右乱闪
// ============================================================================
// flow_fsm.sv — 光流方向投票 + 漏桶积分器 + 显示标签                          // 标题
//                                                                         //
//   每个块矢量出来时，若能量足够且 |u| 超阈值，按符号投一票：                 //   投票规则
//     u<0 -> cnt_left++，u>0 -> cnt_right++，同时写显示标签 RAM。            //
//   每帧结束用票数判定本帧方向（要求单方向票数够多、且比对方多出 MAJORITY 票），//   帧级判定
//   帧方向送入漏桶积分器：连续同向才点亮 LED，静止时向 0 漏电，              //   漏桶
//   单帧/偶发抖动不会导致左右乱闪，且天然保留明确的静止态。                    //
`timescale 1ns/1ps                                                      // 仿真时间精度
module flow_fsm #(                                                      // 模块声明 + 参数
  parameter int NBX     = 20,                                           // 参数：横向块数
  parameter int NBY     = 15,                                           // 参数：纵向块数
  parameter int QF      = 16,                                           // 参数：定点小数位（Q16）
  parameter int TAG_SHIFT = 5,   // 显示块边长 = 2^TAG_SHIFT（全屏 32 / 画中画 8）  // 参数：显示时每块占 2^N 像素
  // 单块可信度：|u| >= U_MIN（定点 Q16，单位：处理域像素/帧）且能量 >= E_MIN   //   单块门槛说明
  // 注：LK 对帧间位移存在低估，U_MIN 设小（0.125 像素/帧），主要靠方向一致性投票。//   为什么阈值低
  parameter int U_MIN   = 8192,                                         // 参数：位移门限 8192/65536 = 0.125 像素/帧
  parameter int E_MIN   = 8000,                                         // 参数：能量门限（纹理太少不可信）
  // 帧方向判定                                                           //   帧级参数
  parameter int CNT_MIN   = 2,   // 单方向至少几票                      // 参数：至少 2 票才算
  parameter int MAJORITY  = 2,   // 优势方向至少多出的票数              // 参数：要比反向多 2 票
  // 漏桶积分器                                                           //   漏桶参数
  parameter int TH_BUCKET  = 3,  // 连续几帧一致才点亮（漏桶阈值）       // 参数：积分到 ±3 才认为"确定在动"
  parameter int BUCKET_MAX = 8   // 漏桶饱和值                          // 参数：最多积到 ±8（防止数值溢出）
)(                                                                      // 参数结束
  input  logic        pclk,                                             // 输入：摄像头时钟（光流结果都在这）
  input  logic        rst_n,                                            // 输入：复位
  input  logic        flow_valid,                                       // 输入：某块的求解结果有效
  input  logic signed [31:0] flow_u,                                    // 输入：该块水平位移（Q16）
  input  logic signed [31:0] flow_v,                                    // 输入：该块垂直位移（本模块没用到）
  input  logic [31:0] flow_energy,                                      // 输入：该块能量
  input  logic [4:0]  flow_bx,                                          // 输入：块列号
  input  logic [3:0]  flow_by,                                          // 输入：块行号
  input  logic        vsync,                                            // 输入：场同步（用来分帧）
  // 显示侧（clk_disp 域读标签）                                            //   显示接口
  input  logic        clk_disp,                                         // 输入：显示时钟
  input  logic [11:0] px,                                               // 输入：显示坐标 x
  input  logic [11:0] py,                                               // 输入：显示坐标 y
  output logic [1:0]  tag_out,                                          // 输出：该点所属块的标签
  // LED                                                                  //   LED 接口
  output logic        led_stop,                                         // 输出：静止
  output logic        led_left,                                         // 输出：向左
  output logic        led_right                                         // 输出：向右
);                                                                      // 端口结束
  localparam int TAG_DEPTH = NBX * NBY;   // 300                        // 常量：标签 RAM 深度 = 20×15

  // =========================================================================
  // 1. 逐块投票 + 标签写 RAM                                               // 第 1 段
  // =========================================================================
  wire moving = (flow_energy >= E_MIN)                                  // 组合：能量够
             && ((flow_u >= U_MIN) || (flow_u <= -U_MIN));              //   且水平位移超过 ±0.125 像素
  wire [1:0] tag = moving ? ((flow_u < 0) ? 2'd1 : 2'd2) : 2'd0;        // 组合：在动 → 负数记 1（左）、正数记 2（右）；不动记 0
  wire [8:0] tag_waddr = ({5'd0, flow_by} * 9'd20) + {4'd0, flow_bx};   // 组合：写地址 = 行号×20 + 列号
  wire [8:0] raddr_disp = ((py >> TAG_SHIFT) * 9'd20) + (px >> TAG_SHIFT);  // 组合：显示地址 = (y/2^N)×20 + (x/2^N)，把每个块放大成 2^N 像素

  logic vsync_d;                                                        // 内部：vsync 延迟一拍
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：延迟
    if (!rst_n) vsync_d <= 1'b0;                                         //   复位清零
    else        vsync_d <= vsync;                                        //   正常打一拍
  end                                                                    //   always 结束
  wire frame_tick = vsync && !vsync_d;                                   // 组合：vsync 上升沿 = 新一帧开始

  logic [8:0] cnt_left, cnt_right;                                       // 内部：本帧左票数、右票数
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：投票计数
    if (!rst_n) begin                                                    //   复位
      cnt_left  <= 9'd0;                                                 //     左票清零
      cnt_right <= 9'd0;                                                 //     右票清零
    end else if (frame_tick) begin                                       //   新一帧开始
      cnt_left  <= 9'd0;                                                 //     左票清零（上一帧的票在这拍已经用过了）
      cnt_right <= 9'd0;                                                 //     右票清零
    end else if (flow_valid && moving) begin                             //   来一个块结果 且 判定为在动
      if (flow_u < 0)                                                    //     往左
        cnt_left  <= cnt_left + 1'b1;                                    //       左票 +1
      else                                                               //     往右
        cnt_right <= cnt_right + 1'b1;                                   //       右票 +1
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  flow_tag_ram #(.DEPTH(TAG_DEPTH)) u_tag (                              // 例化标签 RAM（双时钟）
    .wclk (pclk),                                                        //   写侧：摄像头时钟
    .we   (flow_valid),                                                  //   每个块结果都写
    .waddr(tag_waddr),                                                   //   写地址
    .wdata(tag),                                                         //   写标签 0/1/2
    .rclk (clk_disp),                                                    //   读侧：显示时钟
    .raddr(raddr_disp),                                                  //   读地址
    .rdata(tag_out)                                                      //   输出标签
  );                                                                     //   例化结束

  // =========================================================================
  // 2. 帧方向判定（frame_tick 拍读清零前的计数值）                          // 第 2 段
  // =========================================================================
  wire [8:0] total = cnt_left + cnt_right;                               // 组合：总票数（本设计最终没用到）
  wire frame_left  = (cnt_left  >= CNT_MIN) && (cnt_left  >= cnt_right + MAJORITY);   // 组合：左票够多 且 比右票多至少 2 → 本帧判左
  wire frame_right = (cnt_right >= CNT_MIN) && (cnt_right >= cnt_left  + MAJORITY);   // 组合：右票够多 且 比左票多至少 2 → 本帧判右

  // =========================================================================
  // 3. 漏桶积分器 + LED 输出                                                // 第 3 段
  // =========================================================================
  logic signed [7:0] bucket;                                             // 内部：漏桶（-8..+8）
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：每帧结算一次
    if (!rst_n) begin                                                    //   复位
      bucket <= 8'sd0;                                                   //     回中立
    end else if (frame_tick) begin                                       //   每帧开始时更新（用的是上一帧的判定结果）
      if (frame_left && !frame_right) begin                              //     本帧明确向左
        if (bucket > -BUCKET_MAX)                                        //       还没到负饱和
          bucket <= bucket - 1'b1;                                       //         往负方向加一格
      end else if (frame_right && !frame_left) begin                     //     本帧明确向右
        if (bucket < BUCKET_MAX)                                         //       还没到正饱和
          bucket <= bucket + 1'b1;                                       //         往正方向加一格
      end else begin                                                     //     静止 或 左右矛盾
        // 静止或左右矛盾：向 0 漏电                                     //       说明：这就是"漏桶"名字的由来
        if (bucket > 0)                                                  //       正数
          bucket <= bucket - 1'b1;                                       //         往 0 退一格
        else if (bucket < 0)                                             //       负数
          bucket <= bucket + 1'b1;                                       //         往 0 退一格
      end                                                                //   三分支结束
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  assign led_right = (bucket >= TH_BUCKET);                              // 组合：积分到 +3 才算"确实在向右"
  assign led_left  = (bucket <= -TH_BUCKET);                             // 组合：积分到 -3 才算"确实在向左"
  assign led_stop  = (!led_left) && (!led_right);                        // 组合：两个都不是 → 静止
endmodule                                                               // 模块结束
