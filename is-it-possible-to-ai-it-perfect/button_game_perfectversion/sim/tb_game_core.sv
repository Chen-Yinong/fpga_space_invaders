// tb_game_core.sv — 按键版游戏本体功能仿真
`timescale 1ns/1ps
module tb_game_core;
  localparam int PSLOTS=6, ESLOTS=6, BUNKERS=4;
  logic clk_sys=0, rst_n=0;
  logic btn_left=0, btn_right=0, btn_start=0, btn_restart=0;
  logic [8:0]  player_x; logic player_visible;
  logic [PSLOTS-1:0]   pb_valid; logic [PSLOTS*9-1:0] pb_x, pb_y;
  logic [ESLOTS-1:0]   eb_valid; logic [ESLOTS*9-1:0] eb_x, eb_y;
  logic [54:0] enemy_alive; logic [8:0] enemy_x0, enemy_y0;
  logic [BUNKERS*24*12-1:0] bunker_bits;
  logic [15:0] score; logic [3:0] lives; logic [1:0] state;
  logic ufo_active; logic [8:0] ufo_x;
  logic win;
  logic [1:0] stage; logic stage_show, stage_blink;

  game_core #(.TICK_DIV(10), .PSLOTS(PSLOTS), .ESLOTS(ESLOTS)) dut (.*);

  always #5 clk_sys = ~clk_sys;
  integer errors=0;
  logic ufo_seen = 1'b0;
  always @(posedge clk_sys) if (ufo_active) ufo_seen <= 1'b1;

  task automatic wait_ticks(input int n); repeat(n) repeat(10) @(negedge clk_sys); endtask
  task automatic check(input logic c, input string m);
    if (c) $display("[PASS] %s", m);
    else begin $display("[FAIL] %s", m); errors=errors+1; end
  endtask

  initial begin
    repeat(5) @(negedge clk_sys); rst_n=1'b1; repeat(5) @(negedge clk_sys);

    check(state==2'd0, "reset -> IDLE");
    check(lives==4'd6, "reset -> lives=6");
    check(enemy_alive=={55{1'b1}}, "reset -> 55 enemies");
    check(bunker_bits=={1152{1'b1}}, "reset -> bunkers full");
    check(stage==2'd1, "reset -> stage=1");

    btn_start=1'b1; wait_ticks(3); btn_start=1'b0; wait_ticks(2);
    check(state==2'd1, "start -> PLAY");
    check(win==1'b0, "in play -> win=0");

    wait_ticks(20);
    check(pb_valid != {PSLOTS{1'b0}}, "auto-fire -> player bullets");

    begin
      logic [8:0] p0; p0=player_x;
      btn_left=1'b1; wait_ticks(10); btn_left=1'b0; wait_ticks(2);
      check(player_x < p0, "left -> player moved left");
    end
    begin
      logic [8:0] p1; p1=player_x;
      btn_right=1'b1; wait_ticks(10); btn_right=1'b0; wait_ticks(2);
      check(player_x > p1, "right -> player moved right");
    end

    begin
      int g=0; while (score==0 && g<400) begin wait_ticks(1); g=g+1; end
    end
    check(score>0, "hit enemy -> score up");

    begin
      int g=0; while (eb_valid=={ESLOTS{1'b0}} && g<200) begin wait_ticks(1); g=g+1; end
    end
    check(eb_valid != {ESLOTS{1'b0}}, "enemy fired bullets");

    begin
      int g=0; while (!ufo_seen && g<500) begin wait_ticks(1); g=g+1; end
    end
    check(ufo_seen, "ufo spawned by LFSR");

    begin
      int g=0; while (lives==4'd6 && g<2500) begin wait_ticks(1); g=g+1; end
    end
    check(lives<4'd6, "enemy bullet hit -> lives down");

    if (errors==0) $display("\n==== TB_GAME ALL PASS ====");
    else           $display("\n==== TB_GAME FAILED: %0d ====", errors);
    $finish;
  end

  initial begin
    #200000000; $display("TIMEOUT"); $finish;
  end
endmodule
