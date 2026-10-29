// ============================================================================
// vga_timing.sv —— 逐行注释版（原文件 43 行）★ 坐标系发生器
// 只干一件事：数拍子，输出 x、y 坐标和三个同步信号。不关心画什么。
// 640 可见 + 16 前沿 + 96 同步 + 48 后沿 = 800 拍一行
// 480 可见 + 10 前沿 +  2 同步 + 33 后沿 = 525 行一帧
// 800 × 525 × 60 ≈ 25.2MHz → 所以像素时钟取 25MHz
// ============================================================================
// vga_timing.sv — 标准 VGA 640x480@60 时序发生器（负极性同步）              // 标题
`timescale 1ns/1ps                                                      // 仿真时间精度
module vga_timing #(                                                    // 模块声明 + 参数
  parameter int H_VISIBLE = 640,                                        // 参数：横向可见像素
  parameter int H_FRONT   = 16,                                         // 参数：行前沿（可见区后、同步前）消隐
  parameter int H_SYNC    = 96,                                         // 参数：行同步脉冲宽度
  parameter int H_BACK    = 48,                                         // 参数：行后沿消隐
  parameter int V_VISIBLE = 480,                                        // 参数：纵向可见行数
  parameter int V_FRONT   = 10,                                         // 参数：场前沿消隐
  parameter int V_SYNC    = 2,                                          // 参数：场同步脉冲行数
  parameter int V_BACK    = 33                                          // 参数：场后沿消隐
)(                                                                      // 参数结束
  input  logic        clk_pix,      // 像素时钟 25.175MHz                // 输入：像素时钟（板子给 25MHz，差 0.7% 显示器能接受）
  input  logic        rst_n,                                            // 输入：复位（低有效）
  output logic [11:0] x,                                                // 输出：当前像素 x（0..799，含消隐）
  output logic [11:0] y,                                                // 输出：当前行号 y（0..524，含消隐）
  output logic        hsync,                                            // 输出：行同步（负极性：平时高，同步时低）
  output logic        vsync,                                            // 输出：场同步（负极性）
  output logic        video_active, // 可见像素区                         // 输出：当前是否在 640×480 可见区内
  output logic        frame_start   // 帧首（x=0,y=0）                    // 输出：每帧第一个像素时为 1
);                                                                      // 端口结束
  localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800  // 常量：一行总拍数
  localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525  // 常量：一帧总行数

  logic [11:0] hcnt, vcnt;                                              // 内部：行内计数、行计数
  always_ff @(posedge clk_pix or negedge rst_n) begin                    // 时序逻辑：计数器
    if (!rst_n) begin                                                    //   复位
      hcnt <= '0; vcnt <= '0;                                            //     都清零
    end else if (hcnt == H_TOTAL-1) begin                                //   一行数到最后一拍（799）
      hcnt <= '0;                                                        //     归零
      vcnt <= (vcnt == V_TOTAL-1) ? '0 : vcnt + 1'b1;                    //     行号 +1；到 524 就回 0（新一帧）
    end else begin                                                       //   还没到行尾
      hcnt <= hcnt + 1'b1;                                               //     行内计数 +1
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  assign x = hcnt;                                                       // 组合：x 就是行内计数
  assign y = vcnt;                                                       // 组合：y 就是行号
  assign hsync = ~((hcnt >= H_VISIBLE + H_FRONT) && (hcnt < H_VISIBLE + H_FRONT + H_SYNC));  // 组合：656..751 这 96 拍拉低 → 负极性行同步
  assign vsync = ~((vcnt >= V_VISIBLE + V_FRONT) && (vcnt < V_VISIBLE + V_FRONT + V_SYNC));  // 组合：490..491 这 2 行拉低 → 负极性场同步
  assign video_active = (hcnt < H_VISIBLE) && (vcnt < V_VISIBLE);        // 组合：x<640 且 y<480 才是画面区
  assign frame_start  = (hcnt == 0) && (vcnt == 0);                      // 组合：每帧第一个像素
endmodule                                                               // 模块结束
