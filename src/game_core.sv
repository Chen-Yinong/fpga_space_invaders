// game_core.sv — 按键控制版太空侵略者游戏本体
// 内部坐标 320x240（HDMI 显示 640x480 时 2x 放大）
// 修复：解耦 1152 位掩体动态寻址，彻底根治 Timing Optimization 综合卡死问题
`timescale 1ns/1ps

module game_core #(
  parameter int TICK_DIV    = 833333,   // 50MHz -> 60Hz
  parameter int PSLOTS      = 6,
  parameter int ESLOTS      = 6,
  parameter int FORM_COLS   = 11,
  parameter int FORM_ROWS   = 5,
  parameter int LIVES_INIT  = 6,
  parameter int BUNKERS     = 4,
  parameter int BUNK_W      = 24,
  parameter int BUNK_H      = 12
)(
  input  logic clk_sys,
  input  logic rst_n,
  input  logic btn_left,
  input  logic btn_right,
  input  logic btn_start,
  input  logic btn_restart,
  output logic [8:0]  player_x,
  output logic        player_visible,
  output logic [PSLOTS-1:0]   pb_valid,
  output logic [PSLOTS*9-1:0] pb_x,
  output logic [PSLOTS*9-1:0] pb_y,
  output logic [ESLOTS-1:0]   eb_valid,
  output logic [ESLOTS*9-1:0] eb_x,
  output logic [ESLOTS*9-1:0] eb_y,
  output logic [FORM_COLS*FORM_ROWS-1:0] enemy_alive,
  output logic [8:0]  enemy_x0,
  output logic [8:0]  enemy_y0,
  output logic [BUNKERS*BUNK_W*BUNK_H-1:0] bunker_bits,
  output logic [15:0] score,
  output logic [3:0]  lives,
  output logic [1:0]  state,
  output logic        win,
  output logic        ufo_active,
  output logic [8:0]  ufo_x,
  output logic [1:0]  stage,
  output logic        stage_show,
  output logic        stage_blink
);
  localparam logic [1:0] S_IDLE=2'd0, S_PLAY=2'd1, S_PAUSE=2'd2, S_OVER=2'd3;

  localparam int CELL_W=14, CELL_H=10, COL_GAP=18, ROW_GAP=14;
  localparam int FORM_W = (FORM_COLS-1)*COL_GAP + CELL_W;   // 194
  localparam int X_MIN = 2;
  localparam int X_MAX = 320 - FORM_W - 2;                   // 124
  localparam int FORM_STEP = 2;
  localparam int FORM_DROP = 8;
  localparam int ENEMY_X0_INI = 40;
  localparam int ENEMY_Y0_INI = 40;
  localparam int MOVE_PERIOD = 25;
  localparam int PB_PERIOD = 15;    // 自动连射间隔(tick, 60Hz)
  localparam int EB_PERIOD = 30;
  localparam int PB_SPEED = 5;
  localparam int EB_SPEED = 3;
  localparam int PLAYER_SPEED = 2;
  localparam int PLAYER_HALF = 8;
  localparam int PX_MIN = PLAYER_HALF;
  localparam int PX_MAX = 320 - PLAYER_HALF;
  localparam int PLAYER_Y = 220;
  localparam int INV_FRAMES = 60;
  localparam int BUNK_Y = 180;
  localparam int UFO_SPEED = 4;          // 每 tick 4 像素，较快
  localparam int UFO_Y = 24, UFO_W = 20, UFO_H = 8;   // 顶端横飞
  localparam int UFO_SPAWN_MIN = 200;    // 最小触发间隔(tick)
  localparam int STAGE_CLEAR_TICKS = 120; // 过关过渡时长(2 秒)
  function automatic [8:0] get_bunk_x(input int b);// ---- 修正：严谨固定坐标映射（防止数组下标倒置）----
    case (b)
      0: return 9'd32;
      1: return 9'd108;
      2: return 9'd184;
      default: return 9'd260;
    endcase
  endfunction

  // ---- 60Hz tick ----
  logic [31:0] tick_cnt; logic tick;
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin tick_cnt<='0; tick<=1'b0; end
    else if (tick_cnt >= TICK_DIV-1) begin tick_cnt<='0; tick<=1'b1; end
    else begin tick_cnt<=tick_cnt+1'b1; tick<=1'b0; end

  // ---- 按键边沿 / 计数器 ----
  logic btn_start_d, btn_restart_d;
  logic [7:0] pb_cnt, eb_cnt, inv_cnt;
  logic [15:0] move_cnt;
  logic dir;
  logic [15:0] lfsr;
  logic        stage_clear;
  logic [7:0]  stage_clear_cnt;

  // ---- 关卡难度参数（外星人移动/投弹加快，末关玩家射速上调、投弹放慢）----
  logic [7:0] mv_period, eb_period, pb_period, pb_speed;
  always_comb begin
    case (stage)
      2'd2: begin mv_period=8'd20; eb_period=8'd24; pb_period=8'd15; pb_speed=8'd5; end
      2'd3: begin mv_period=8'd15; eb_period=8'd40; pb_period=8'd10; pb_speed=8'd7; end
      default: begin mv_period=8'd25; eb_period=8'd30; pb_period=8'd15; pb_speed=8'd5; end
    endcase
  end

  // ---- 空闲子弹槽 ----
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

  // ---- 列/行坐标预计算（寄存，缩短碰撞路径）----
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

  // ---- 玩家子弹 x 外星人碰撞（组合，浅层）----
  logic [PSLOTS-1:0] pb_hit_c;
  logic [6:0] pb_idx_c [PSLOTS];
  always_comb begin
    for (int i=0;i<PSLOTS;i++) begin
      pb_hit_c[i]=1'b0; pb_idx_c[i]=7'd0;
      if (pb_valid[i]) begin
        for (int r=0;r<FORM_ROWS;r++) for (int c=0;c<FORM_COLS;c++) begin
          automatic int id = r*FORM_COLS+c;
          automatic int ex = col_lx[c];
          automatic int ey = row_ty[r];
          automatic int bx = pb_x[9*i +: 9];
          automatic int by = pb_y[9*i +: 9];
          if (!pb_hit_c[i] && enemy_alive[id] &&
              bx >= ex && bx < ex+CELL_W && by >= ey && by < ey+CELL_H) begin
            pb_hit_c[i] = 1'b1;
            pb_idx_c[i] = id[6:0];
          end
        end
      end
    end
  end

  // ---- 碰撞结果寄存一级 ----
  logic [PSLOTS-1:0] pb_hit;
  logic [6:0] pb_idx [PSLOTS];
  always_ff @(posedge clk_sys or negedge rst_n)
    if (!rst_n) begin
      pb_hit<='0;
      for (int i=0;i<PSLOTS;i++) pb_idx[i]<=7'd0;
    end else begin
      pb_hit<=pb_hit_c;
      for (int i=0;i<PSLOTS;i++) pb_idx[i]<=pb_idx_c[i];
    end

  // ---- 命中计分（每只 10 分）----
  logic [15:0] score_delta;
  always_comb begin
    score_delta=16'd0;
    for (int i=0;i<PSLOTS;i++) if (pb_hit[i]) score_delta=score_delta+16'd10;
  end

  // ---- 敌弹 x 玩家碰撞 ----
  logic eb_hit_any;
  always_comb begin
    eb_hit_any=1'b0;
    if (inv_cnt==8'd0) begin
      for (int i=0;i<ESLOTS;i++) begin
        automatic int ex = eb_x[9*i +: 9];
        automatic int ey = eb_y[9*i +: 9];
        if (eb_valid[i] && ex >= player_x-PLAYER_HALF && ex < player_x+PLAYER_HALF &&
            ey >= PLAYER_Y-12 && ey < PLAYER_Y+2)
          eb_hit_any=1'b1;
      end
    end
  end

  // ---- 敌机发射者（随机列的最底存活行）----
  logic [3:0] rnd_col;
  always_comb rnd_col = (lfsr[3:0] >= 4'd11) ? (lfsr[3:0]-4'd11) : lfsr[3:0];
  logic [2:0] shooter_row; logic shooter_ok;
  always_comb begin
    shooter_ok=1'b0; shooter_row=3'd0;
    for (int r=FORM_ROWS-1; r>=0; r--) begin
      if (!shooter_ok && enemy_alive[r*FORM_COLS + rnd_col]) begin
        shooter_ok=1'b1; shooter_row=r[2:0];
      end
    end
  end

  // ---- 辅助函数：提取指定掩体 b、局部列 lx 的 12 位纵向像素状态 ----
  function automatic logic [BUNK_H-1:0] get_bunk_col(input int b, input logic [4:0] lx);
    logic [BUNK_H-1:0] col_bits;
    col_bits = '0;
    for (int yy = 0; yy < BUNK_H; yy++) begin
      if (lx < BUNK_W)
        col_bits[yy] = bunker_bits[b*BUNK_W*BUNK_H + yy*BUNK_W + int'(lx)];
    end
    return col_bits;
  endfunction

  // ---- 玩家子弹撞掩体检测（仅当该列对应高度仍有掩体像素时才触发）----
  logic [PSLOTS-1:0] pb_bhit;
  logic [1:0] pb_bid [PSLOTS];
  logic [4:0] pb_blx [PSLOTS];
  logic [3:0] pb_bly [PSLOTS];
  always_comb begin
    for (int i=0; i<PSLOTS; i++) begin
      pb_bhit[i]=1'b0; pb_bid[i]=2'd0; pb_blx[i]=5'd0; pb_bly[i]=4'd0;
      if (pb_valid[i]) begin
        automatic int bx = pb_x[9*i +: 9];
        automatic int by = pb_y[9*i +: 9];
        for (int b=0; b<BUNKERS; b++) begin
          automatic int bx_base = get_bunk_x(b);
          if (!pb_bhit[i] && (bx >= bx_base) && (bx < bx_base + BUNK_W) &&
              (by >= BUNK_Y) && (by < BUNK_Y + BUNK_H)) begin
            automatic logic [4:0] lx = 5'(bx - bx_base);
            automatic logic [3:0] ly = 4'(by - BUNK_Y);
            automatic logic [BUNK_H-1:0] col_bits = get_bunk_col(b, lx);
            // 补偿 PB_SPEED=5 步长：若 ly<=2 则顺带检查顶边 yy=0..1，只有存在像素(1'b1)才判定碰撞
            automatic logic [3:0] check_y = (ly <= 4'd2) ? 4'd0 : ly;
            if ((col_bits >> check_y) != '0) begin
              pb_bhit[i] = 1'b1;
              pb_bid[i]  = b[1:0];
              pb_blx[i]  = lx;
              pb_bly[i]  = check_y;
            end
          end
        end
      end
    end
  end

  // ---- 敌弹撞掩体检测（仅当该列对应高度仍有掩体像素时才触发）----
  logic [ESLOTS-1:0] eb_bhit;
  logic [1:0] eb_bid [ESLOTS];
  logic [4:0] eb_blx [ESLOTS];
  logic [3:0] eb_bly [ESLOTS];
  always_comb begin
    for (int i=0; i<ESLOTS; i++) begin
      eb_bhit[i]=1'b0; eb_bid[i]=2'd0; eb_blx[i]=5'd0; eb_bly[i]=4'd0;
      if (eb_valid[i]) begin
        automatic int ex = eb_x[9*i +: 9];
        automatic int ey = eb_y[9*i +: 9];
        for (int b=0; b<BUNKERS; b++) begin
          automatic int bx_base = get_bunk_x(b);
          if (!eb_bhit[i] && (ex >= bx_base) && (ex < bx_base + BUNK_W) &&
              (ey >= BUNK_Y) && (ey < BUNK_Y + BUNK_H)) begin
            automatic logic [4:0] lx = 5'(ex - bx_base);
            automatic logic [3:0] ly = 4'(ey - BUNK_Y);
            automatic logic [BUNK_H-1:0] col_bits = get_bunk_col(b, lx);
            // 检查从顶边 0 到 ly+2 范围内是否还有未销毁的掩体像素
            automatic logic [3:0] hit_end = (ly + 4'd2 >= BUNK_H) ? 4'(BUNK_H-1) : (ly + 4'd2);
            if ((col_bits & ((12'h1 << (hit_end + 1'b1)) - 12'h1)) != '0) begin
              eb_bhit[i] = 1'b1;
              eb_bid[i]  = b[1:0];
              eb_blx[i]  = lx;
              eb_bly[i]  = hit_end;
            end
          end
        end
      end
    end
  end

  // ---- 提取本帧击中掩体的子弹坐标（化简为单事件，彻底消灭 1152 位 MUX）----
  logic       pb_hit_bunker_en;
  logic [1:0] pb_hit_bid;
  logic [4:0] pb_hit_lx;
  logic [3:0] pb_hit_ly;
  always_comb begin
    pb_hit_bunker_en = 1'b0;
    pb_hit_bid       = 2'd0;
    pb_hit_lx        = 5'd0;
    pb_hit_ly        = 4'd0;
    for (int i=0; i<PSLOTS; i++) begin
      if (!pb_hit_bunker_en && pb_bhit[i]) begin
        pb_hit_bunker_en = 1'b1;
        pb_hit_bid       = pb_bid[i];
        pb_hit_lx        = pb_blx[i];
        pb_hit_ly        = pb_bly[i];
      end
    end
  end

  logic       eb_hit_bunker_en;
  logic [1:0] eb_hit_bid;
  logic [4:0] eb_hit_lx;
  logic [3:0] eb_hit_ly;
  always_comb begin
    eb_hit_bunker_en = 1'b0;
    eb_hit_bid       = 2'd0;
    eb_hit_lx        = 5'd0;
    eb_hit_ly        = 4'd0;
    for (int i=0; i<ESLOTS; i++) begin
      if (!eb_hit_bunker_en && eb_bhit[i]) begin
        eb_hit_bunker_en = 1'b1;
        eb_hit_bid       = eb_bid[i];
        eb_hit_lx        = eb_blx[i];
        eb_hit_ly        = eb_bly[i];
      end
    end
  end

  wire alien_crush = (enemy_y0 + (FORM_ROWS-1)*ROW_GAP + CELL_H >= BUNK_Y);
  assign player_visible = (inv_cnt==8'd0) | inv_cnt[4];

  // ---- 神秘飞碟（LFSR 随机触发 + 随机大奖）----
  logic        ufo_active_r;
  logic [8:0]  ufo_x_r;
  logic [15:0] ufo_spawn_cnt;
  logic [8:0]  ufo_pts;
  always_comb case (lfsr[1:0])
    2'd0: ufo_pts = 9'd50;
    2'd1: ufo_pts = 9'd100;
    2'd2: ufo_pts = 9'd150;
    default: ufo_pts = 9'd300;
  endcase

  logic [PSLOTS-1:0] ufo_hit_pb;
  always_comb begin
    for (int i=0;i<PSLOTS;i++) begin
      ufo_hit_pb[i] = ufo_active_r && pb_valid[i] &&
        (pb_x[9*i +: 9] >= ufo_x_r) && (pb_x[9*i +: 9] < ufo_x_r + UFO_W) &&
        (pb_y[9*i +: 9] >= UFO_Y) && (pb_y[9*i +: 9] < UFO_Y + UFO_H);
    end
  end
  logic ufo_hit_any;
  always_comb ufo_hit_any = |ufo_hit_pb;
  assign ufo_active = ufo_active_r;
  assign ufo_x = ufo_x_r;
  assign stage_show = stage_clear;
  assign stage_blink = stage_clear_cnt[4];

  // ---- 主状态机与时序逻辑 ----
  always_ff @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
      state          <= S_IDLE;
      player_x       <= 9'd160;
      pb_valid       <= '0;
      pb_x           <= '0;
      pb_y           <= '0;
      eb_valid       <= '0;
      eb_x           <= '0;
      eb_y           <= '0;
      enemy_alive    <= {FORM_COLS*FORM_ROWS{1'b1}};
      enemy_x0       <= ENEMY_X0_INI[8:0];
      enemy_y0       <= ENEMY_Y0_INI[8:0];
      bunker_bits    <= '1;
      score          <= '0;
      lives          <= LIVES_INIT[3:0];
      move_cnt       <= '0;
      dir            <= 1'b0;
      pb_cnt         <= '0;
      eb_cnt         <= '0;
      inv_cnt        <= '0;
      btn_start_d    <= 1'b0;
      btn_restart_d  <= 1'b0;
      lfsr           <= 16'hACE1;
      win            <= 1'b0;
      stage          <= 2'd1;
      stage_clear    <= 1'b0;
      stage_clear_cnt<= 8'd0;
      ufo_active_r   <= 1'b0;
      ufo_x_r        <= 9'd0;
      ufo_spawn_cnt  <= UFO_SPAWN_MIN[15:0];
    end else if (tick) begin
      btn_start_d   <= btn_start;
      btn_restart_d <= btn_restart;
      lfsr          <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
      if (inv_cnt != 0) inv_cnt <= inv_cnt - 1'b1;

      if (btn_restart & ~btn_restart_d) begin
        // 重开
        state       <= S_PLAY;
        player_x    <= 9'd160;
        pb_valid    <= '0;
        eb_valid    <= '0;
        enemy_alive <= {FORM_COLS*FORM_ROWS{1'b1}};
        enemy_x0    <= ENEMY_X0_INI[8:0];
        enemy_y0    <= ENEMY_Y0_INI[8:0];
        bunker_bits <= '1;
        score       <= '0;
        lives       <= LIVES_INIT[3:0];
        move_cnt    <= '0;
        dir         <= 1'b0;
        pb_cnt      <= '0;
        eb_cnt      <= '0;
        inv_cnt     <= '0;
        ufo_active_r  <= 1'b0;
        ufo_x_r       <= 9'd0;
        ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0];
        win           <= 1'b0;
        stage         <= 2'd1;
        stage_clear   <= 1'b0;
        stage_clear_cnt<= 8'd0;
      end
      else if (btn_start & ~btn_start_d) begin
        if (state==S_IDLE || state==S_OVER) begin
          state       <= S_PLAY;
          player_x    <= 9'd160;
          pb_valid    <= '0;
          eb_valid    <= '0;
          enemy_alive <= {FORM_COLS*FORM_ROWS{1'b1}};
          enemy_x0    <= ENEMY_X0_INI[8:0];
          enemy_y0    <= ENEMY_Y0_INI[8:0];
          bunker_bits <= '1;
          score       <= '0;
          lives       <= LIVES_INIT[3:0];
          move_cnt    <= '0;
          dir         <= 1'b0;
          pb_cnt      <= '0;
          eb_cnt      <= '0;
          inv_cnt     <= '0;
          ufo_active_r  <= 1'b0;
          ufo_x_r       <= 9'd0;
          ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0];
          win           <= 1'b0;
          stage         <= 2'd1;
          stage_clear   <= 1'b0;
          stage_clear_cnt<= 8'd0;
        end else if (state==S_PLAY)  state <= S_PAUSE;
        else if (state==S_PAUSE)     state <= S_PLAY;
      end
      else if (state==S_PLAY) begin
        if (stage_clear) begin
          // 过关过渡：屏幕闪烁显示 Stage N，2 秒后进下一关
          if (stage_clear_cnt >= STAGE_CLEAR_TICKS-1) begin
            stage_clear     <= 1'b0;
            stage_clear_cnt <= 8'd0;
            stage           <= stage + 1'b1;
            enemy_alive     <= {FORM_COLS*FORM_ROWS{1'b1}};
            enemy_x0        <= ENEMY_X0_INI[8:0];
            enemy_y0        <= ENEMY_Y0_INI[8:0] + stage*FORM_DROP;
            bunker_bits     <= '1;
            lives           <= LIVES_INIT[3:0];
            pb_valid        <= '0;
            eb_valid        <= '0;
            move_cnt        <= '0;
            dir             <= 1'b0;
            pb_cnt          <= '0;
            eb_cnt          <= '0;
            inv_cnt         <= '0;
          end else begin
            stage_clear_cnt <= stage_clear_cnt + 1'b1;
          end
        end else begin
        // 1. 玩家移动
        if (btn_left && player_x > PX_MIN)
          player_x <= player_x - PLAYER_SPEED;
        else if (btn_right && player_x < PX_MAX)
          player_x <= player_x + PLAYER_SPEED;

        // 2. 自动连射
        if (pb_cnt >= pb_period-1) begin
          pb_cnt <= '0;
          if (pb_found) begin
            pb_valid[pb_free]           <= 1'b1;
            pb_x[9*pb_free +: 9]        <= player_x;
            pb_y[9*pb_free +: 9]        <= PLAYER_Y[8:0] - 9'd8;
          end
        end else begin
          pb_cnt <= pb_cnt + 1'b1;
        end

        // 3. 玩家子弹移动与命中销毁
        for (int i=0; i<PSLOTS; i++) begin
          if (pb_valid[i]) begin
            if (pb_y[9*i +: 9] < pb_speed)
              pb_valid[i] <= 1'b0;
            else
              pb_y[9*i +: 9] <= pb_y[9*i +: 9] - pb_speed;
          end
          if (pb_hit[i]) begin
            pb_valid[i]            <= 1'b0;
            enemy_alive[pb_idx[i]] <= 1'b0;
          end
          if (pb_bhit[i]) begin
            pb_valid[i] <= 1'b0; // 撞掩体销毁
          end
        end
        // UFO 命中：销毁子弹 + 随机大奖
        if (ufo_hit_any) begin
          ufo_active_r <= 1'b0;
          for (int i=0;i<PSLOTS;i++) if (ufo_hit_pb[i]) pb_valid[i] <= 1'b0;
        end
        score <= score + score_delta + (ufo_hit_any ? {7'b0, ufo_pts} : 16'd0);

        // UFO 移动 / 随机触发
        if (ufo_active_r) begin
          if (ufo_x_r + UFO_SPEED > 320) begin
            ufo_active_r  <= 1'b0;
            ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0] + {5'b0, lfsr[10:0]};
          end else begin
            ufo_x_r <= ufo_x_r + UFO_SPEED;
          end
        end else begin
          if (ufo_spawn_cnt == 16'd0) begin
            ufo_active_r  <= 1'b1;
            ufo_x_r       <= 9'd0;
            ufo_spawn_cnt <= UFO_SPAWN_MIN[15:0] + {5'b0, lfsr[10:0]};
          end else begin
            ufo_spawn_cnt <= ufo_spawn_cnt - 1'b1;
          end
        end

        // 4. 外星人整体平移与触边下落
        if (move_cnt >= mv_period-1) begin
          move_cnt <= '0;
          if (!dir) begin
            if (enemy_x0 + FORM_STEP > X_MAX) begin
              dir      <= 1'b1;
              enemy_y0 <= enemy_y0 + FORM_DROP;
            end else begin
              enemy_x0 <= enemy_x0 + FORM_STEP;
            end
          end else begin
            if (enemy_x0 < X_MIN + FORM_STEP) begin
              dir      <= 1'b0;
              enemy_y0 <= enemy_y0 + FORM_DROP;
            end else begin
              enemy_x0 <= enemy_x0 - FORM_STEP;
            end
          end
        end else begin
          move_cnt <= move_cnt + 1'b1;
        end

        // 5. 敌机发射子弹
        if (eb_cnt >= eb_period-1) begin
          eb_cnt <= '0;
          if (shooter_ok && eb_found) begin
            eb_valid[eb_free]    <= 1'b1;
            eb_x[9*eb_free +: 9] <= enemy_x0 + rnd_col*COL_GAP + CELL_W/2;
            eb_y[9*eb_free +: 9] <= enemy_y0 + shooter_row*ROW_GAP + CELL_H;
          end
        end else begin
          eb_cnt <= eb_cnt + 1'b1;
        end

        // 6. 敌弹移动与命中销毁
        for (int i=0; i<ESLOTS; i++) begin
          if (eb_valid[i]) begin
            if (eb_y[9*i +: 9] > 9'd236)
              eb_valid[i] <= 1'b0;
            else
              eb_y[9*i +: 9] <= eb_y[9*i +: 9] + EB_SPEED;
          end
          if (eb_bhit[i]) begin
            eb_valid[i] <= 1'b0; // 撞掩体销毁
          end
        end
        if (eb_hit_any) begin
          lives   <= lives - 1'b1;
          inv_cnt <= INV_FRAMES[7:0];
          for (int i=0; i<ESLOTS; i++) eb_valid[i] <= 1'b0;
        end

        // 7. 掩体像素更新（消除隧穿：玩家子弹削底边，敌弹削顶边）
        for (int b = 0; b < BUNKERS; b++) begin
          automatic int bx_base = get_bunk_x(b);
          for (int yy = 0; yy < BUNK_H; yy++) begin
            for (int xx = 0; xx < BUNK_W; xx++) begin
              automatic int idx = b*BUNK_W*BUNK_H + yy*BUNK_W + xx;
              automatic int wx  = bx_base + xx;

              // 外星人触碰整列碾碎（优先级最高）
              if (alien_crush && (wx >= enemy_x0) && (wx < enemy_x0 + FORM_W))
                bunker_bits[idx] <= 1'b0;
              // 玩家激光向上击中：横向 3 像素，从碰撞点往下打通到底边
              else if (pb_hit_bunker_en && (pb_hit_bid == b[1:0]) &&
                       (xx + 1 >= pb_hit_lx) && (xx <= pb_hit_lx + 1) && (yy >= pb_hit_ly))
                bunker_bits[idx] <= 1'b0;
                // 敌机炸弹向下砸中：横向 3 像素，从顶边砸到碰撞点
              else if (eb_hit_bunker_en && (eb_hit_bid == b[1:0]) &&
                       (xx + 1 >= eb_hit_lx) && (xx <= eb_hit_lx + 1) && (yy <= eb_hit_ly))
                bunker_bits[idx] <= 1'b0;
            end
          end
        end
        
        // 8. 胜负终局裁决
        if (lives == 4'd0) begin
          state <= S_OVER;
          win   <= 1'b0;
        end else if (enemy_y0 + (FORM_ROWS-1)*ROW_GAP + CELL_H >= PLAYER_Y) begin
          state <= S_OVER;
          win   <= 1'b0;
        end else if (enemy_alive == '0) begin
          if (stage == 2'd3) begin
            state <= S_OVER;
            win   <= 1'b1;
          end else begin
            stage_clear     <= 1'b1;
            stage_clear_cnt <= 8'd0;
          end
        end
        end
      end
    end
  end

endmodule
