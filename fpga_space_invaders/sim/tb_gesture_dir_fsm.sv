// tb_gesture_dir_fsm.sv
// 验证 gesture_dir_fsm 的迟滞、去抖与命令编码。
// 仿真：Vivado xsim（见 README 或 docs/environment_setup.md）
`timescale 1ns/1ps

module tb_gesture_dir_fsm;

  logic              clk_sys = 0;
  logic              rst_n   = 0;
  logic              frame_tick = 0;
  logic              feat_valid = 0;
  logic signed [11:0] dx = 0;
  logic        [9:0] tip_dist = 0;
  logic              cmd_valid;
  logic        [3:0] cmd;

  gesture_dir_fsm dut (.*);

  always #5 clk_sys = ~clk_sys;   // 100 MHz

  // 每帧：先给 dx/dist/feat_valid，再给一个 frame_tick 脉冲
  task automatic frame(input logic signed [11:0] d,
                       input logic v = 1'b1,
                       input logic [9:0] dd = 10'd100);
    @(negedge clk_sys);
    dx <= d; feat_valid <= v; tip_dist <= dd;
    @(negedge clk_sys);
    frame_tick <= 1'b1;
    @(negedge clk_sys);
    frame_tick <= 1'b0;
    #1;   // 让组合输出稳定
  endtask

  task automatic check(input logic [3:0] exp_cmd,
                       input logic       exp_valid,
                       input string      msg);
    if (cmd !== exp_cmd || cmd_valid !== exp_valid) begin
      $error("%s: 期望 cmd=%b valid=%b，实际 cmd=%b valid=%b (t=%0t)",
             msg, exp_cmd, exp_valid, cmd, cmd_valid, $time);
    end else begin
      $display("[PASS] %s  cmd=%b valid=%b (t=%0t)", msg, cmd, cmd_valid, $time);
    end
  endtask

  initial begin
    repeat (4) @(negedge clk_sys);
    rst_n = 1'b1;
    repeat (4) @(negedge clk_sys);

    // 1) 死区内不动：|dx| < EXIT_TH
    repeat (10) frame(12'd2);
    check(4'b0000, 1'b0, "死区内保持 idle");

    // 2) 左移：连续 6 帧 dx=-120（超过 ENTER_TH）
    repeat (6) frame(-12'd120);
    check(4'b0001, 1'b1, "进入左移");

    // 3) 仍左移：dx=-60（仍小于 -EXIT_TH，保持在左区）
    repeat (3) frame(-12'd60);
    check(4'b0001, 1'b1, "左区保持");

    // 4) 回到死区 4 帧 -> 退回 idle
    repeat (4) frame(12'd5);
    check(4'b0000, 1'b0, "死区退回 idle");

    // 5) 右移
    repeat (6) frame(12'd120);
    check(4'b0010, 1'b1, "进入右移");

    // 6) 手丢失（feat_valid=0）应保持右移命令
    repeat (2) frame(12'd0, 1'b0, 10'd0);
    check(4'b0010, 1'b1, "手丢失保持右移");

    // 7) 恢复，dx=0 死区 -> 4 帧后 idle
    repeat (4) frame(12'd0, 1'b1, 10'd100);
    check(4'b0000, 1'b0, "恢复后回 idle");

    $display("TB DONE");
    $finish;
  end

  // 超时保护
  initial begin
    #2000000;
    $display("TIMEOUT");
    $finish;
  end
endmodule