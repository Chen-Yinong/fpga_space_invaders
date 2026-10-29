// ============================================================================
// div_pipe.sv —— 逐行注释版（原文件 84 行）★ 定点除法器（恢复余数法，流水线）
// 为什么不用 "/"：FPGA 的除法综合出来要么是天价的除法器 IP，要么是几十级组合逻辑，
//                时序根本跑不到 100MHz 以上。这里手写一个每拍做一位的迭代除法。
// 原理（恢复余数法 / restoring division）：
//   被除数 = |num| << QF（左移 QF 位，把小数的精度"放大"16 倍）
//   每一拍：把余数左移一位、拼上商寄存器最高位，试减除数；
//           够减（没借位）→ 商这一位记 1；不够减（有借位）→ 商记 0，并把余数加回来（"恢复"）
//   做 N = W+QF 拍，正好把 QF 位小数也算出来。
//   最后按符号位取反，并饱和到 32 位（防止溢出）。
// ============================================================================
// div_pipe.sv — 流水线恢复除法器：signed / signed -> 32bit 定点商（Q=QF）    // 标题
//   被除数 = |num| << QF（W+QF 位），除数 = |den|（W 位），                  // 说明被除数怎么放大
//   N = W+QF 拍后得到无符号商，再按符号位取反并饱和到 32bit。                 // 说明结果怎么处理
`timescale 1ns/1ps                                                      // 仿真时间精度
module div_pipe #(                                                      // 模块声明 + 参数
  parameter int W  = 54,   // 数值位宽（signed）                          // 参数：操作数位宽（必须能放下 54 位乘积）
  parameter int QF = 16    // 定点小数位                                  // 参数：结果保留 16 位小数（Q16 = 1/65536 精度）
)(                                                                      // 参数结束
  input  logic                clk,                                      // 输入：时钟
  input  logic                rst_n,                                    // 输入：复位
  input  logic                start,                                    // 输入：启动一次除法（单拍）
  input  logic signed [W-1:0] num,                                      // 输入：被除数（有符号）
  input  logic signed [W-1:0] den,                                      // 输入：除数（有符号）
  output logic                done,                                     // 输出：计算完成（单拍脉冲）
  output logic signed [31:0]  quot,                                     // 输出：商（Q16 定点）
  output logic                div_by_zero                               // 输出：除数为 0 的标志
);                                                                      // 端口结束
  localparam int N = W + QF;                                            // 常量：一共要做 N 拍（54+16 = 70 拍）

  logic          busy;                                                  // 内部：正在算标志
  logic [6:0]    step;                                                  // 内部：做到第几位（7 位够表示 0..69）
  logic [W-1:0]  den_abs;                                               // 内部：除数的绝对值（启动时锁存）
  logic [N-1:0]  quo_reg;                                               // 内部：商寄存器 + 被除数移位寄存器（70 位）
  logic [W:0]    rem;                                                   // 内部：余数（W+1 位，多一位用来判断借位）
  logic          neg;                                                   // 内部：结果符号（启动时算好）

  wire [W-1:0] num_abs_w = num[W-1] ? (~num + 1'b1) : num;              // 组合：被除数取绝对值（负数 → 按位取反加 1）
  wire [W-1:0] den_abs_w = den[W-1] ? (~den + 1'b1) : den;              // 组合：除数取绝对值
  wire [N-1:0] num_sh    = {num_abs_w, {QF{1'b0}}};                     // 组合：被除数左移 QF 位（后面补 16 个 0）= 乘 65536

  wire [W:0] rem_sh = {rem[W-1:0], quo_reg[N-1]};                       // 组合：余数左移一位，最低位补商寄存器的最高位（被除数逐位进余数）
  wire [W:0] rem_su = rem_sh - {1'b0, den_abs};                         // 组合：试减除数（扩成 W+1 位做减法）
  wire borrow = rem_su[W];                                              // 组合：最高位是 1 说明不够减（有借位）

  always_ff @(posedge clk or negedge rst_n) begin                        // 时序逻辑：除法主流程
    if (!rst_n) begin                                                    //   复位
      busy        <= 1'b0;                                               //     空闲
      step        <= '0;                                                 //     步数清零
      done        <= 1'b0;                                               //     完成标志清零
      quot        <= 32'sd0;                                             //     商清零
      div_by_zero <= 1'b0;                                               //     除零标志清零
      rem         <= '0;                                                 //     余数清零
      quo_reg     <= '0;                                                 //     商寄存器清零
      den_abs     <= '0;                                                 //     除数绝对值清零
      neg         <= 1'b0;                                               //     符号清零
    end else begin                                                       //   正常
      done <= 1'b0;                                                      //     完成标志默认只亮一拍
      if (start && !busy) begin                                          //     启动且空闲
        busy        <= 1'b1;                                             //       进入忙状态
        step        <= '0;                                               //       步数从 0 开始
        rem         <= '0;                                               //       余数清零
        den_abs     <= den_abs_w;                                        //       锁存除数绝对值
        quo_reg     <= num_sh;                                           //       被除数（已左移 QF 位）进商寄存器
        neg         <= (num[W-1] ^ den[W-1]) && (den != 0) && (num != 0);  //     结果符号 = 两操作数符号异或；除零或除数为 0 时不置负
        div_by_zero <= (den == 0);                                       //       记录是否除零
      end else if (busy) begin                                           //     正在计算
        if (step < N) begin                                              //       还没做满 N 拍
          step <= step + 1'b1;                                           //         步数 +1
          if (borrow) begin                                              //         不够减（有借位）
            rem     <= rem_su + {1'b0, den_abs};                         //           把余数加回来（"恢复余数"）→ 相当于不改
            quo_reg <= {quo_reg[N-2:0], 1'b0};                           //           商这一位记 0
          end else begin                                                 //         够减
            rem     <= rem_su;                                           //           余数更新为减去除数后的值
            quo_reg <= {quo_reg[N-2:0], 1'b1};                           //           商这一位记 1
          end                                                            //         if 结束
        end else begin                                                   //       做满 N 拍 → 收尾
          busy <= 1'b0;                                                  //         退出忙状态
          done <= 1'b1;                                                  //         拉高完成标志（单拍）
          if (neg) begin                                                 //         结果是负数
            if (quo_reg[31:0] > 32'h7FFFFFFF)                            //           低 32 位超过 0x7FFFFFFF
              quot <= 32'h80000000;                                      //             饱和到最小负数（防止取反溢出）
            else                                                         //           否则
              quot <= -$signed(quo_reg[31:0]);                           //             取反得到正确符号
          end else begin                                                 //         结果是正数
            if (quo_reg[31:0] > 32'h7FFFFFFF)                            //           低 32 位超过最大值
              quot <= 32'h7FFFFFFF;                                      //             饱和到最大正数
            else                                                         //           否则
              quot <= $signed(quo_reg[31:0]);                            //             直接输出
          end                                                            //         符号处理结束
        end                                                              //       收尾 if 结束
      end                                                                //     busy if 结束
    end                                                                  //   复位/正常结束
  end                                                                    //   always 结束
endmodule                                                               // 模块结束
