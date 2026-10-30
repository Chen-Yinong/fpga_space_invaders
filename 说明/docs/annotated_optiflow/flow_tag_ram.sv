// ============================================================================
// flow_tag_ram.sv —— 逐行注释版（原文件 25 行）★ 双时钟双口 RAM
// 作用：把 300 个块的判定结果（静止/左/右）存起来，让显示端能随时读出来画矢量场
// 写侧在摄像头时钟（pclk），读侧在显示时钟（clk_disp），两边互不干扰
// ============================================================================
// flow_tag_ram.sv — 块运动标签双口 RAM（300 深 × 2bit）                    // 标题
//   写侧 pclk：0=静止/低能，1=明显左移，2=明显右移                          // 写入的数据含义
//   读侧 clk_disp：供 HDMI 运动场可视化                                    // 读侧用途
`timescale 1ns/1ps                                                      // 仿真时间精度
module flow_tag_ram #(                                                  // 模块声明 + 参数
  parameter int DEPTH = 300                                             // 参数：300 个块 = 20 列 × 15 行
)(                                                                      // 参数结束
  input  logic        wclk,                                             // 输入：写时钟（摄像头像素时钟）
  input  logic        we,                                               // 输入：写使能
  input  logic [8:0]  waddr,                                            // 输入：写地址（0..299）
  input  logic [1:0]  wdata,                                            // 输入：写数据（0/1/2）
  input  logic        rclk,                                             // 输入：读时钟（显示时钟）
  input  logic [8:0]  raddr,                                            // 输入：读地址
  output logic [1:0]  rdata                                             // 输出：读出的标签
);                                                                      // 端口结束
  (* ram_style = "block" *) logic [1:0] mem [0:DEPTH-1];                // 内部：存储体；ram_style 属性要求综合成块 RAM（BRAM）

  always_ff @(posedge wclk) begin                                       // 时序逻辑：写口
    if (we) mem[waddr] <= wdata;                                        //   写使能时写入（没有复位，因为整块很快会被覆盖）
  end                                                                   //   always 结束

  always_ff @(posedge rclk) begin                                       // 时序逻辑：读口
    rdata <= mem[raddr];                                                //   每个读时钟都读一次（1 拍延迟）
  end                                                                   //   always 结束
endmodule                                                               // 模块结束
