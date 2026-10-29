// ============================================================================
// flow_linebuf.sv —— 逐行注释版（原文件 29 行）★ 光流用的"延迟一行"缓冲
// 作用：把输入数据整体延迟 DEPTH 个使能周期。DEPTH=320（处理域一行宽）
// 就相当于"上一行的同一个像素"。四个例化叠起来就能拿到 y、y-1、y-2 三行。
// ============================================================================
// flow_linebuf.sv — 处理域行缓冲（SRL 推断），en 每拍推进一次               // 标题
//   输出 q = 延迟 DEPTH 个使能周期后的输入。                                // 说明：只有 en 为高的拍才移位
`timescale 1ns/1ps                                                      // 仿真时间精度
module flow_linebuf #(                                                  // 模块声明 + 参数
  parameter int DEPTH = 320,                                            // 参数：延迟多少拍（一行像素数）
  parameter int W     = 8                                               // 参数：数据位宽（灰度 8 位）
)(                                                                      // 参数结束
  input  logic         clk,                                             // 输入：时钟
  input  logic         rst_n,                                           // 输入：复位（低有效）
  input  logic         en,                                              // 输入：移位使能（每个处理域像素来一次）
  input  logic [W-1:0] d,                                               // 输入：新数据
  output logic [W-1:0] q                                                // 输出：延迟后的数据
);                                                                      // 端口结束
  (* srl_style = "srl" *) logic [W-1:0] mem [0:DEPTH-1];                // 内部：存储体；srl_style 属性提示综合器用 LUT 里的移位寄存器（SRL）实现，不占 BRAM
  integer i;                                                            // 内部：循环变量（注意是 integer 不是 int，为了兼容 Verilog）

  always_ff @(posedge clk or negedge rst_n) begin                        // 时序逻辑：整体移位
    if (!rst_n) begin                                                    //   复位
      for (i = 0; i < DEPTH; i = i + 1)                                  //     遍历所有单元
        mem[i] <= '0;                                                    //       全部清零
    end else if (en) begin                                               //   有使能时才动
      for (i = DEPTH-1; i > 0; i = i - 1)                                //     从尾往头遍历
        mem[i] <= mem[i-1];                                              //       每个单元接受前一个的值 = 整体后移一格
      mem[0] <= d;                                                       //     新数据进第 0 格
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  assign q = mem[DEPTH-1];                                              // 组合：输出最末尾那一格 = 延迟 DEPTH 拍的数据
endmodule                                                               // 模块结束
