// tb_dir_judge.sv — 验证手势方向判定的迟滞与去抖
`timescale 1ns/1ps
module tb_dir_judge;
  logic pclk=0, rst_n=0, frame_tick=0, valid=0;
  logic signed [10:0] dx=0;
  logic move_left, move_right;

  dir_judge dut (.*);
  always #20 pclk = ~pclk;

  integer errors=0;

  task automatic frame(input logic signed [10:0] d, input logic v);
    @(negedge pclk); dx<=d; valid<=v;
    @(negedge pclk); frame_tick<=1'b1;
    @(negedge pclk); frame_tick<=1'b0;
    repeat(2) @(posedge pclk);
  endtask

  task automatic check(input logic l, input logic r, input string m);
    if (move_left!==l || move_right!==r) begin
      $display("[FAIL] %s  L=%b R=%b", m, move_left, move_right);
      errors=errors+1;
    end else $display("[PASS] %s", m);
  endtask

  initial begin
    repeat(4) @(negedge pclk); rst_n=1'b1;
    repeat(4) @(negedge pclk);

    frame(0, 0);       check(1'b0,1'b0,"no hand -> stop");
    frame(-11'sd20,1); check(1'b1,1'b0,"enter left");
    frame(-11'sd6,1);  check(1'b1,1'b0,"hold left (hysteresis)");
    repeat(4) frame(0,1); check(1'b0,1'b0,"back to idle");
    frame(11'sd20,1);  check(1'b0,1'b1,"enter right");
    repeat(4) frame(0,1); check(1'b0,1'b0,"right back to idle");

    if (errors==0) $display("\n==== TB_DIR_ALL_PASS ====");
    else           $display("\n==== TB_DIR_FAILED %0d ====", errors);
    $finish;
  end

  initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
