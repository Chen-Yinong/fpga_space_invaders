// tb_dir_judge_acc.sv —— 慢速积分版方向判定的功能验证
// 覆盖：静止抖动不误触发 / 慢速漂移出脉冲 / 中速连续 / 快速立即 / 换向 / 无手清零
`timescale 1ns/1ps
module tb_dir_judge_acc;
  logic pclk = 0, rst_n = 0, frame_tick = 0, valid = 0;
  logic signed [10:0] dx = 0;
  logic move_left, move_right;

  dir_judge_acc dut (
    .pclk(pclk), .rst_n(rst_n), .frame_tick(frame_tick),
    .valid(valid), .dx(dx),
    .move_left(move_left), .move_right(move_right)
  );

  always #10 pclk = ~pclk;  // 50MHz

  task automatic tick(input logic signed [10:0] d, input logic v);
    begin
      @(negedge pclk); dx = d; valid = v; frame_tick = 1;
      @(negedge pclk); frame_tick = 0;
    end
  endtask

  integer errors = 0;
  integer i, burst_cnt, max_burst, total_left;
  integer rand_dx;
  logic was_left;

  initial begin
    repeat (5) @(negedge pclk);
    rst_n = 1;
    repeat (2) @(negedge pclk);

    // ---- 1. 规律抖动 ±2 交替 80 帧：不许动 ----
    for (i = 0; i < 40; i = i + 1) begin
      tick(2, 1); if (move_left || move_right) begin
        errors++; $display("[%0t] FAIL1 规律抖动触发 move", $time);
      end
      tick(-2, 1); if (move_left || move_right) begin
        errors++; $display("[%0t] FAIL1 规律抖动触发 move", $time);
      end
    end
    $display("CHECK1 规律抖动 ±2 x80: %s", errors ? "FAIL" : "PASS");

    // ---- 2. 随机抖动 [-3,3] 300 帧（板上实测幅度）：不许动 ----
    // 注意 $random%N 是有符号取模，范围是 -(N-1)..(N-1)，先映射到无符号再平移
    for (i = 0; i < 300; i = i + 1) begin
      rand_dx = ({$random} % 7) - 3;  // {$random} 转无符号 → 0..6，减 3 → -3..+3
      tick(rand_dx, 1);
      if (move_left || move_right) begin
        errors++; $display("[%0t] FAIL2 随机抖动触发 move (dx=%0d)", $time, rand_dx);
      end
    end
    $display("CHECK2 随机抖动±3 x300: %s", errors ? "FAIL" : "PASS");

    // ---- 3. 慢速漂移 -3px/帧 60 帧：必须出现左移脉冲，但脉冲式（非连续不断）----
    burst_cnt = 0; max_burst = 0; total_left = 0; was_left = 0;
    for (i = 0; i < 60; i = i + 1) begin
      tick(-3, 1);
      if (move_left) begin
        total_left++; burst_cnt++;
        if (burst_cnt > max_burst) max_burst = burst_cnt;
        was_left = 1;
      end else burst_cnt = 0;
      if (move_right) begin errors++; $display("[%0t] FAIL3 慢速左漂判成右移", $time); end
    end
    if (total_left == 0) begin errors++; $display("FAIL3 慢速左漂 60 帧从未触发"); end
    if (max_burst > 8)   begin errors++; $display("FAIL3 慢速左漂变成连续(max_burst=%0d)", max_burst); end
    $display("CHECK3 慢速 -3px/帧x60: %s (触发帧数=%0d, 最长连续=%0d)",
             (total_left>0 && max_burst<=8) ? "PASS" : "FAIL", total_left, max_burst);

    // ---- 4. 中速 -5px/帧：短暂积累后应连续左移 ----
    for (i = 0; i < 16; i = i + 1) tick(-5, 1);
    if (!move_left) begin errors++; $display("FAIL4 中速 -5px/帧x16 未连续左移"); end
    $display("CHECK4 中速 -5px/帧: %s", move_left ? "PASS" : "FAIL");

    // ---- 5. 快速 -15px/帧：1 帧立即左移 ----
    for (i = 0; i < 6; i = i + 1) tick(0, 1);  // 静止 6 帧确保退出 S_LEFT
    tick(-15, 1);
    if (!move_left) begin errors++; $display("FAIL5 快速 -15 未立即左移"); end
    $display("CHECK5 快速 -15px/帧: %s", move_left ? "PASS" : "FAIL");

    // ---- 6. 快速反向 +15：应切到右移 ----
    tick(15, 1);
    if (!move_right || move_left) begin errors++; $display("FAIL6 反向未切换"); end
    $display("CHECK6 快速反向切换: %s", (move_right && !move_left) ? "PASS" : "FAIL");

    // ---- 7. valid=0（手离开）：3 帧内回 IDLE ----
    for (i = 0; i < 5; i = i + 1) tick(0, 0);
    if (move_left || move_right) begin errors++; $display("FAIL7 无手未回 IDLE"); end
    $display("CHECK7 无手回 IDLE: %s", (move_left||move_right) ? "FAIL" : "PASS");

    // ---- 8. 右侧慢速 +3px/帧 对称性：应出右移脉冲、绝不出左移 ----
    total_left = 0;  // 复用作 total_right 计数
    for (i = 0; i < 60; i = i + 1) begin
      tick(3, 1);
      if (move_left) begin errors++; $display("[%0t] FAIL8 右漂判左", $time); end
      if (move_right) total_left++;
    end
    if (total_left == 0) begin errors++; $display("FAIL8 右漂 60 帧从未触发右移"); end
    $display("CHECK8 慢速 +3px/帧x60 右移脉冲: %s (触发帧数=%0d)",
             (total_left>0) ? "PASS" : "FAIL", total_left);

    $display("==== TB RESULT: %0d ERRORS ====", errors);
    $finish;
  end
endmodule
