// ============================================================================
// gray_framebuf.sv —— 逐行注释版（原文件 59 行）★ 双缓冲灰度帧缓存
// 为什么需要它：算时间梯度 It 要知道"上一帧同一位置"的灰度，所以必须存一整帧
// 尺寸：320×240 = 76800 像素 × 8 位 = 600Kbit，用 BRAM 存
// 乒乓原理：偶数帧写 mem0 读 mem1；奇数帧写 mem1 读 mem0 —— 同一个 RAM 口
//           在前半帧写、后半帧读也不冲突，因为读写不同帧
// ============================================================================
// gray_framebuf.sv — 双缓冲灰度帧缓存（2 × DW*DH × 8bit）                  // 标题
//   vsync 上升沿翻转 ping-pong：偶数帧写 mem0 读 mem1，奇数帧反之。          // 乒乓说明
//   读地址与写地址同拍给出（raddr 通常接 waddr），读数据 1 拍后有效。          // 时序说明
`timescale 1ns/1ps                                                      // 仿真时间精度
module gray_framebuf #(                                                 // 模块声明 + 参数
  parameter int DW = 320,                                               // 参数：处理域宽
  parameter int DH = 240,                                               // 参数：处理域高
  parameter int AW = 17                                                 // 参数：地址位宽（2^17 = 131072 > 76800）
)(                                                                      // 参数结束
  input  logic         pclk,                                            // 输入：像素时钟
  input  logic         rst_n,                                           // 输入：复位
  input  logic         vsync,                                           // 输入：场同步（用来切帧）
  input  logic         wr_en,                                           // 输入：写使能（处理域像素有效）
  input  logic [AW-1:0] waddr,                                          // 输入：写地址
  input  logic [7:0]   gray_in,                                         // 输入：当前帧灰度
  input  logic [AW-1:0] raddr,                                          // 输入：读地址
  output logic [7:0]   gray_out                                         // 输出：上一帧灰度
);                                                                      // 端口结束
  localparam int DEPTH = DW * DH;                                       // 常量：一帧像素数 = 76800

  logic frame_sel;                                                      // 内部：当前写哪一块（0=mem0，1=mem1）
  logic vsync_d;                                                        // 内部：vsync 延迟一拍，用于检测上升沿
  always_ff @(posedge pclk or negedge rst_n) begin                        // 时序逻辑：乒乓切换
    if (!rst_n) begin                                                    //   复位
      frame_sel <= 1'b0;                                                 //     默认写 mem0
      vsync_d   <= 1'b0;                                                 //     vsync 延迟清零
    end else begin                                                       //   正常
      vsync_d <= vsync;                                                  //     vsync 打一拍
      if (vsync && !vsync_d)                                             //     检测到 vsync 上升沿（新一帧开始）
        frame_sel <= ~frame_sel;                                         //       翻转：这一帧写另一块
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  (* ram_style = "block" *) logic [7:0] mem0 [0:DEPTH-1];                // 内部：第一块帧缓存（强制用 BRAM）
  (* ram_style = "block" *) logic [7:0] mem1 [0:DEPTH-1];                // 内部：第二块帧缓存
  logic [7:0] rd0, rd1;                                                  // 内部：两块各自的读数据

  // mem0：偶数帧写当前帧，奇数帧读上一帧（单端口分时）                     // 第 1 块：分时复用
  always_ff @(posedge pclk) begin                                        // 时序逻辑：mem0 一个口两种用途
    if (frame_sel == 1'b0) begin                                         //   本帧正在写 mem0
      if (wr_en)                                                         //     有像素来时
        mem0[waddr] <= gray_in;                                          //       写入当前帧灰度
    end else begin                                                       //   本帧在读 mem0（它存的是上一帧）
      rd0 <= rst_n ? mem0[raddr] : 8'd0;                                 //     读出上一帧同位置灰度；复位期间强制读 0
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  // mem1：奇数帧写当前帧，偶数帧读上一帧（单端口分时）                     // 第 2 块：与 mem0 完全对称
  always_ff @(posedge pclk) begin                                        // 时序逻辑：mem1
    if (frame_sel == 1'b1) begin                                         //   本帧正在写 mem1
      if (wr_en)                                                         //     有像素来时
        mem1[waddr] <= gray_in;                                          //       写入
    end else begin                                                       //   本帧在读 mem1
      rd1 <= rst_n ? mem1[raddr] : 8'd0;                                 //     读出上一帧
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  assign gray_out = (frame_sel == 1'b0) ? rd1 : rd0;                     // 组合：正在写 mem0 时，上一帧在 mem1 → 输出 rd1；反之输出 rd0
endmodule                                                               // 模块结束
