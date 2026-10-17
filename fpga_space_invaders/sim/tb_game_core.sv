// tb_game_core.sv — game_core v2 功能仿真
`timescale 1ns/1ps
module tb_game_core;
  localparam int PSLOTS=6, ESLOTS=3;
  logic        clk_sys=0, rst_n=0;
  logic [1:0]  move_cmd=2'b00;
  logic        btn_start=0;
  logic [8:0]  player_x; logic player_visible;
  logic [PSLOTS-1:0]   pb_valid; logic [PSLOTS*9-1:0] pb_x, pb_y;
  logic [ESLOTS-1:0]   eb_valid; logic [ESLOTS*9-1:0] eb_x, eb_y;
  logic [49:0] enemy_alive; logic [8:0] enemy_x0, enemy_y0;
  logic [15:0] score; logic [3:0] lives; logic [2:0] wave; logic [1:0] state;

  game_core #(.TICK_DIV(10), .MOVE_PERIOD(8), .PB_PERIOD(4), .EB_PERIOD(6), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) dut (.*);

  always #5 clk_sys = ~clk_sys;
  int errors=0;

  task automatic wait_ticks(input int n); repeat(n) repeat(10) @(negedge clk_sys); endtask
  task automatic check(input logic c, input string m);
    if (c) $display("[PASS] %s", m); else begin $display("[FAIL] %s", m); errors=errors+1; end
  endtask

  initial begin
    repeat(5) @(negedge clk_sys); rst_n=1'b1; repeat(5) @(negedge clk_sys);

    check(state==2'd0, "reset -> IDLE");
    check(lives==4'd3, "reset -> lives=3");
    check(wave==3'd1, "reset -> wave=1");
    check(enemy_alive=={50{1'b1}}, "reset -> enemies full");

    btn_start=1'b1; wait_ticks(3); btn_start=1'b0; wait_ticks(2);
    check(state==2'd1, "start -> PLAY");

    wait_ticks(12);
    check(pb_valid != {PSLOTS{1'b0}}, "auto-fire -> player bullets exist");

    begin logic [8:0] p0; p0=player_x;
      move_cmd=2'b01; wait_ticks(8); move_cmd=2'b00; wait_ticks(2);
      check(player_x < p0, "move_cmd=left -> player moved left"); end

    begin logic [8:0] p1; p1=player_x;
      move_cmd=2'b10; wait_ticks(8); move_cmd=2'b00; wait_ticks(2);
      check(player_x > p1, "move_cmd=right -> player moved right"); end

    begin automatic int g=0; while (score==0 && g<800) begin wait_ticks(1); g=g+1; end end
    check(score>0, "bullet hit enemy -> score up");

    begin automatic int g=0; while (eb_valid==0 && g<800) begin wait_ticks(1); g=g+1; end end
    check(eb_valid != {ESLOTS{1'b0}}, "enemy fired bullets");

    begin automatic int g=0; while (lives==4'd3 && g<6000) begin wait_ticks(1); g=g+1; end end
    check(lives < 4'd3, "enemy bullet hit player -> lives down");

    if (errors==0) $display("\n==== TB ALL PASS ====");
    else           $display("\n==== TB FAILED: %0d ====", errors);
    $finish;
  end

  initial begin #500000000; $display("TIMEOUT"); $finish; end
endmodule