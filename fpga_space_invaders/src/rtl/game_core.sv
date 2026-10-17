// game_core.sv — 游戏本体 v2
// 输入: move_cmd[1:0] (00 停 / 01 左 / 10 右) + btn_start（上升沿：开始/暂停/继续/重开）
// 特性: 自动连射(多颗子弹) + 敌机子弹 + 生命/无敌 + 波次/难度 + 输赢
`timescale 1ns/1ps
module game_core #(
  parameter int TICK_DIV     = 833333,   // 50MHz -> 60Hz
  parameter int PSLOTS       = 6,        // 玩家子弹槽位
  parameter int ESLOTS       = 3,        // 敌机子弹槽位
  parameter int PB_PERIOD    = 20,       // 玩家自动连射间隔(tick)
  parameter int EB_PERIOD    = 20,       // 敌机发射间隔(tick)
  parameter int PB_SPEED     = 5,
  parameter int EB_SPEED     = 4,
  parameter int PLAYER_SPEED = 2,
  parameter int PLAYER_HALF  = 8,
  parameter int PLAYER_Y     = 220,
  parameter int COL_GAP      = 24,
  parameter int ROW_GAP      = 20,
  parameter int CELL_W       = 16,
  parameter int CELL_H       = 12,
  parameter int FORM_COLS    = 10,
  parameter int FORM_ROWS    = 5,
  parameter int FORM_STEP    = 4,
  parameter int FORM_DROP    = 12,
  parameter int MOVE_PERIOD  = 30,
  parameter int LIVES_INIT   = 3,
  parameter int INV_FRAMES   = 60,
  parameter int MAX_WAVE     = 3,
  parameter int ENEMY_X0_INI = 40,
  parameter int ENEMY_Y0_INI = 40
)(
  input  logic              clk_sys,
  input  logic              rst_n,
  input  logic [1:0]        move_cmd,
  input  logic              btn_start,
  output logic [8:0]        player_x,
  output logic              player_visible,
  output logic [PSLOTS-1:0] pb_valid,
  output logic [PSLOTS*9-1:0] pb_x,
  output logic [PSLOTS*9-1:0] pb_y,
  output logic [ESLOTS-1:0] eb_valid,
  output logic [ESLOTS*9-1:0] eb_x,
  output logic [ESLOTS*9-1:0] eb_y,
  output logic [49:0]       enemy_alive,
  output logic [8:0]        enemy_x0,
  output logic [8:0]        enemy_y0,
  output logic [15:0]       score,
  output logic [3:0]        lives,
  output logic [2:0]        wave,
  output logic [1:0]        state
);
  localparam logic [1:0] S_IDLE=2'd0, S_PLAY=2'd1, S_PAUSE=2'd2, S_OVER=2'd3;
  localparam int FORM_W = (FORM_COLS-1)*COL_GAP + CELL_W;   // 232
  localparam int X_MIN  = 4;
  localparam int X_MAX  = 320 - FORM_W - 4;                 // 84
  localparam int PX_MIN = PLAYER_HALF;
  localparam int PX_MAX = 320 - PLAYER_HALF;

  // ---------- 60Hz tick ----------
  logic [31:0] tick_cnt; logic tick;
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin tick_cnt<='0; tick<=1'b0; end
    else if (tick_cnt >= TICK_DIV-1) begin tick_cnt<='0; tick<=1'b1; end
    else begin tick_cnt<=tick_cnt+1'b1; tick<=1'b0; end

  // ---------- 状态 ----------
  logic        btn_start_d;
  logic [15:0] move_cnt;
  logic        dir;
  logic [7:0]  pb_cnt, eb_cnt;
  logic [7:0]  inv_cnt;
  logic [15:0] lfsr;
  logic [15:0] mv_period;

  always_comb mv_period = (MOVE_PERIOD > (wave-1)*4) ? (MOVE_PERIOD - (wave-1)*4) : 16'd10;

  // ---------- 空闲子弹槽 ----------
  logic [3:0] pb_free; logic pb_found;
  always_comb begin
    pb_found=1'b0; pb_free=4'd0;
    for (int i=0;i<PSLOTS;i++) if (!pb_found && !pb_valid[i]) begin pb_found=1'b1; pb_free=i[3:0]; end
  end
  logic [3:0] eb_free; logic eb_found;
  always_comb begin
    eb_found=1'b0; eb_free=4'd0;
    for (int i=0;i<ESLOTS;i++) if (!eb_found && !eb_valid[i]) begin eb_found=1'b1; eb_free=i[3:0]; end
  end

  // ---------- 列/行 坐标预计算（寄存，缩短碰撞路径）----------
  logic [8:0] col_lx [0:FORM_COLS-1];
  logic [8:0] row_ty [0:FORM_ROWS-1];
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin
      for (int c=0;c<FORM_COLS;c++) col_lx[c] <= 9'd0;
      for (int r=0;r<FORM_ROWS;r++) row_ty[r] <= 9'd0;
    end else if (tick) begin
      for (int c=0;c<FORM_COLS;c++) col_lx[c] <= enemy_x0 + c*COL_GAP;
      for (int r=0;r<FORM_ROWS;r++) row_ty[r] <= enemy_y0 + r*ROW_GAP;
    end

  // ---------- 子弹 x 敌机 碰撞（组合，浅层：用寄存好的 col_lx/row_ty）----------
  logic [PSLOTS-1:0] pb_hit_c;
  logic [5:0]        pb_idx_c [PSLOTS];
  always_comb begin
    for (int i=0;i<PSLOTS;i++) begin
      pb_hit_c[i]=1'b0; pb_idx_c[i]=6'd0;
      if (pb_valid[i]) begin
        for (int r=0;r<FORM_ROWS;r++) begin
          for (int c=0;c<FORM_COLS;c++) begin
            automatic int id = r*FORM_COLS+c;
            automatic int ex = col_lx[c];
            automatic int ey = row_ty[r];
            automatic int bx = pb_x[9*i +: 9];
            automatic int by = pb_y[9*i +: 9];
            if (!pb_hit_c[i] && enemy_alive[id] &&
                bx >= ex && bx < ex+CELL_W && by >= ey && by < ey+CELL_H) begin
              pb_hit_c[i] = 1'b1;
              pb_idx_c[i] = id[5:0];
            end
          end
        end
      end
    end
  end

  // ---------- 碰撞结果寄存一级（流水，供 tick 时使用）----------
  logic [PSLOTS-1:0] pb_hit;
  logic [5:0]        pb_idx [PSLOTS];
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin
      pb_hit <= '0;
      for (int i=0;i<PSLOTS;i++) pb_idx[i] <= 6'd0;
    end else begin
      pb_hit <= pb_hit_c;
      for (int i=0;i<PSLOTS;i++) pb_idx[i] <= pb_idx_c[i];
    end

  // ---------- 命中计分（用寄存后的结果，浅层）----------
  function automatic logic [15:0] pts_of(input logic [5:0] id);
    pts_of = (id < 6'd10) ? 16'd30 : (id < 6'd30) ? 16'd20 : 16'd10;
  endfunction
  logic [15:0] score_delta;
  always_comb begin
    score_delta = 16'd0;
    for (int i=0;i<PSLOTS;i++)
      if (pb_hit[i]) score_delta = score_delta + pts_of(pb_idx[i]);
  end

  // ---------- 敌弹 x 玩家 碰撞 ----------
  logic eb_hit_any;
  always_comb begin
    eb_hit_any = 1'b0;
    if (inv_cnt == 8'd0) begin
      for (int i=0;i<ESLOTS;i++) begin
        automatic int ex = eb_x[9*i +: 9];
        automatic int ey = eb_y[9*i +: 9];
        if (eb_valid[i] &&
            ex >= player_x-PLAYER_HALF && ex < player_x+PLAYER_HALF &&
            ey >= PLAYER_Y-12 && ey < PLAYER_Y+2)
          eb_hit_any = 1'b1;
      end
    end
  end

  // ---------- 敌机发射者（随机一列中最低那只）----------
  logic [3:0] rnd_col;
  always_comb rnd_col = (lfsr[3:0] >= 4'd10) ? (lfsr[3:0]-4'd10) : lfsr[3:0];
  logic [2:0] shooter_row; logic shooter_ok;
  always_comb begin
    shooter_ok=1'b0; shooter_row=3'd0;
    for (int r=FORM_ROWS-1; r>=0; r--) begin
      if (!shooter_ok && enemy_alive[r*FORM_COLS + rnd_col]) begin
        shooter_ok=1'b1; shooter_row=r[2:0];
      end
    end
  end

  assign player_visible = (inv_cnt == 8'd0) | inv_cnt[4];

  // ---------- 主逻辑 ----------
  always_ff @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
      state<=S_IDLE; player_x<=9'd160; pb_valid<='0; pb_x<='0; pb_y<='0;
      eb_valid<='0; eb_x<='0; eb_y<='0;
      enemy_alive<={50{1'b1}}; enemy_x0<=ENEMY_X0_INI[8:0]; enemy_y0<=ENEMY_Y0_INI[8:0];
      score<='0; lives<=LIVES_INIT[3:0]; wave<=3'd1;
      move_cnt<='0; dir<=1'b0; pb_cnt<='0; eb_cnt<='0; inv_cnt<='0;
      btn_start_d<=1'b0; lfsr<=16'hACE1;
    end else if (tick) begin
      btn_start_d <= btn_start;
      lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
      if (inv_cnt != 0) inv_cnt <= inv_cnt - 1'b1;

      if (btn_start & ~btn_start_d) begin
        if (state==S_IDLE || state==S_OVER) begin
          state<=S_PLAY; player_x<=9'd160; pb_valid<='0; eb_valid<='0;
          enemy_alive<={50{1'b1}}; enemy_x0<=ENEMY_X0_INI[8:0]; enemy_y0<=ENEMY_Y0_INI[8:0];
          score<='0; lives<=LIVES_INIT[3:0]; wave<=3'd1;
          move_cnt<='0; dir<=1'b0; pb_cnt<='0; eb_cnt<='0; inv_cnt<='0;
        end else if (state==S_PLAY) state<=S_PAUSE;
        else if (state==S_PAUSE) state<=S_PLAY;
      end else if (state==S_PLAY) begin
        // 玩家移动
        if (move_cmd==2'b01 && player_x > PX_MIN) player_x <= player_x - PLAYER_SPEED;
        else if (move_cmd==2'b10 && player_x < PX_MAX) player_x <= player_x + PLAYER_SPEED;

        // 自动连射
        if (pb_cnt >= PB_PERIOD-1) begin
          pb_cnt <= '0;
          if (pb_found) begin
            pb_valid[pb_free] <= 1'b1;
            pb_x[9*pb_free +: 9] <= player_x;
            pb_y[9*pb_free +: 9] <= PLAYER_Y[8:0] - 9'd8;
          end
        end else pb_cnt <= pb_cnt + 1'b1;

        // 玩家子弹移动 + 命中
        for (int i=0;i<PSLOTS;i++) begin
          if (pb_valid[i]) begin
            if (pb_y[9*i +: 9] < PB_SPEED) pb_valid[i] <= 1'b0;
            else pb_y[9*i +: 9] <= pb_y[9*i +: 9] - PB_SPEED;
          end
          if (pb_hit[i]) begin
            pb_valid[i] <= 1'b0;
            enemy_alive[pb_idx[i]] <= 1'b0;
          end
        end
        if (score_delta != 0) score <= score + score_delta;

        // 敌机整体移动（速度随波次变快）
        if (move_cnt >= mv_period-1) begin
          move_cnt <= '0;
          if (!dir) begin
            if (enemy_x0 + FORM_STEP > X_MAX) begin dir<=1'b1; enemy_y0<=enemy_y0+FORM_DROP; end
            else enemy_x0 <= enemy_x0 + FORM_STEP;
          end else begin
            if (enemy_x0 < X_MIN + FORM_STEP) begin dir<=1'b0; enemy_y0<=enemy_y0+FORM_DROP; end
            else enemy_x0 <= enemy_x0 - FORM_STEP;
          end
        end else move_cnt <= move_cnt + 1'b1;

        // 敌机发射
        if (eb_cnt >= EB_PERIOD-1) begin
          eb_cnt <= '0;
          if (shooter_ok && eb_found) begin
            eb_valid[eb_free] <= 1'b1;
            eb_x[9*eb_free +: 9] <= enemy_x0 + rnd_col*COL_GAP + CELL_W/2;
            eb_y[9*eb_free +: 9] <= enemy_y0 + shooter_row*ROW_GAP + CELL_H;
          end
        end else eb_cnt <= eb_cnt + 1'b1;

        // 敌弹移动 + 命中玩家
        for (int i=0;i<ESLOTS;i++) begin
          if (eb_valid[i]) begin
            if (eb_y[9*i +: 9] > 9'd236) eb_valid[i] <= 1'b0;
            else eb_y[9*i +: 9] <= eb_y[9*i +: 9] + EB_SPEED;
          end
        end
        if (eb_hit_any) begin
          lives <= lives - 1'b1;
          inv_cnt <= INV_FRAMES[7:0];
          for (int i=0;i<ESLOTS;i++) eb_valid[i] <= 1'b0;
        end

        // 输赢 / 波次
        if (lives == 4'd0) state <= S_OVER;
        else if (enemy_y0 + (FORM_ROWS-1)*ROW_GAP + CELL_H >= PLAYER_Y) state <= S_OVER;
        else if (enemy_alive == '0) begin
          if (wave >= MAX_WAVE[2:0]) state <= S_OVER;
          else begin
            wave <= wave + 1'b1;
            enemy_alive <= {50{1'b1}};
            enemy_x0 <= ENEMY_X0_INI[8:0];
            enemy_y0 <= ENEMY_Y0_INI[8:0];
            pb_valid <= '0; eb_valid <= '0;
            move_cnt <= '0; dir <= 1'b0;
          end
        end
      end
    end
  end
endmodule