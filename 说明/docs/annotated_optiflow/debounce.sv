// ============================================================================
// debounce.sv —— 逐行注释版（原文件 23 行）★ 按键消抖
// 原理：机械按键按下/松开瞬间会抖十几个毫秒，F P G A 跑几十兆，
//       不消抖一次按下会被当成几百次。做法是"电平必须稳定够久才认"。
// ============================================================================
// debounce.sv — 按键消抖（电平稳定 CNT 个时钟才认可）                       // 标题
`timescale 1ns/1ps                                                      // 仿真时间精度
module debounce #(                                                      // 模块声明 + 参数
  parameter int CNT = 500000     // 5ms @100MHz                          // 参数：稳定多少拍才认可（默认 100MHz 下 50 万拍 = 5ms）
)(                                                                      // 参数结束
  input  logic clk,                                                     // 输入：时钟
  input  logic rst_n,                                                   // 输入：复位（低有效）
  input  logic btn_in,                                                  // 输入：原始按键电平（调用方已把"低有效"取反成"高=按下"）
  output logic btn_out                                                  // 输出：消抖后的稳定电平
);                                                                      // 端口结束
  logic [31:0] cnt;                                                     // 内部：稳定计数器
  logic        btn_sync;                                                // 内部：同步后的输入
  always_ff @(posedge clk or negedge rst_n)                             // 时序逻辑：异步输入先打一拍（抑制亚稳态，单级同步）
    if (!rst_n) btn_sync <= 1'b0; else btn_sync <= btn_in;              //   复位清零，否则每拍采样

  always_ff @(posedge clk or negedge rst_n) begin                        // 时序逻辑：消抖主逻辑
    if (!rst_n) begin cnt <= '0; btn_out <= 1'b0; end                   //   复位：计数清零、输出 0
    else if (btn_sync != btn_out) begin                                 //   输入与当前输出不一致 → 按键可能刚变
      if (cnt == CNT-1) begin cnt <= '0; btn_out <= btn_sync; end       //     已经稳定 CNT 拍 → 接受新电平，计数归零
      else cnt <= cnt + 1'b1;                                           //     还没稳定够 → 继续数
    end else cnt <= '0;                                                 //   输入与输出一致 → 计数清零（不数）
  end                                                                   //   always 结束
endmodule                                                               // 模块结束
