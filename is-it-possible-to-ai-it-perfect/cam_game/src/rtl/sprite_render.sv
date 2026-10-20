// sprite_render.sv — 黑白二色太空侵略者渲染（外星人/玩家/子弹/掩体/HUD）
// 内部坐标 320x240，显示 640x480 时 2x 放大
`timescale 1ns/1ps
module sprite_render #(
  parameter int PSLOTS = 6,
  parameter int ESLOTS = 6,
  parameter int FORM_COLS = 11,
  parameter int FORM_ROWS = 5,
  parameter int BUNKERS = 4
)(
  input  logic [9:0]  vid_x, vid_y,
  input  logic [8:0]  player_x,
  input  logic        player_visible,
  input  logic [PSLOTS-1:0]   pb_valid,
  input  logic [PSLOTS*9-1:0] pb_x,
  input  logic [PSLOTS*9-1:0] pb_y,
  input  logic [ESLOTS-1:0]   eb_valid,
  input  logic [ESLOTS*9-1:0] eb_x,
  input  logic [ESLOTS*9-1:0] eb_y,
  input  logic [FORM_COLS*FORM_ROWS-1:0] enemy_alive,
  input  logic [8:0]  enemy_x0,
  input  logic [8:0]  enemy_y0,
  input  logic [BUNKERS*24*12-1:0] bunker_bits,
  input  logic [15:0] score,
  input  logic [3:0]  lives,
  input  logic [1:0]  state,
  input  logic        win,
  input  logic        ufo_active,
  input  logic [8:0]  ufo_x,
  input  logic [1:0]  stage,
  input  logic        stage_show,
  input  logic        stage_blink,
  output logic [23:0] rgb
);
  localparam int BUNK_W = 24, BUNK_H = 12, BUNK_Y = 180;
  localparam int BUNK_X [0:BUNKERS-1] = '{32, 108, 184, 260};
  localparam int CELL_W = 14, CELL_H = 10, COL_GAP = 18, ROW_GAP = 14;
  localparam int PLAYER_Y = 220, PLAYER_HALF = 8;
  localparam int UFO_Y = 24, UFO_W = 20, UFO_H = 8;

  logic [8:0] gx, gy;
  assign gx = vid_x[9:1];
  assign gy = vid_y[8:1];

  // ---- 8x8 数字字模（bit7 = 最左列）----
  function automatic logic [7:0] font_row(input logic [3:0] d, input logic [2:0] r);
    case (d)
      4'd0: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h6E; 3'd3:font_row=8'h76; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase
      4'd1: case (r) 3'd0:font_row=8'h18; 3'd1:font_row=8'h38; 3'd2:font_row=8'h18; 3'd3:font_row=8'h18; 3'd4:font_row=8'h18; 3'd5:font_row=8'h18; 3'd6:font_row=8'h7E; default:font_row=8'h00; endcase
      4'd2: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h06; 3'd3:font_row=8'h0C; 3'd4:font_row=8'h30; 3'd5:font_row=8'h60; 3'd6:font_row=8'h7E; default:font_row=8'h00; endcase
      4'd3: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h06; 3'd3:font_row=8'h1C; 3'd4:font_row=8'h06; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase
      4'd4: case (r) 3'd0:font_row=8'h0C; 3'd1:font_row=8'h1C; 3'd2:font_row=8'h3C; 3'd3:font_row=8'h6C; 3'd4:font_row=8'h7E; 3'd5:font_row=8'h0C; 3'd6:font_row=8'h0C; default:font_row=8'h00; endcase
      4'd5: case (r) 3'd0:font_row=8'h7E; 3'd1:font_row=8'h60; 3'd2:font_row=8'h7C; 3'd3:font_row=8'h06; 3'd4:font_row=8'h06; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase
      4'd6: case (r) 3'd0:font_row=8'h1C; 3'd1:font_row=8'h30; 3'd2:font_row=8'h60; 3'd3:font_row=8'h7C; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase
      4'd7: case (r) 3'd0:font_row=8'h7E; 3'd1:font_row=8'h66; 3'd2:font_row=8'h0C; 3'd3:font_row=8'h18; 3'd4:font_row=8'h18; 3'd5:font_row=8'h18; 3'd6:font_row=8'h18; default:font_row=8'h00; endcase
      4'd8: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h66; 3'd3:font_row=8'h3C; 3'd4:font_row=8'h66; 3'd5:font_row=8'h66; 3'd6:font_row=8'h3C; default:font_row=8'h00; endcase
      4'd9: case (r) 3'd0:font_row=8'h3C; 3'd1:font_row=8'h66; 3'd2:font_row=8'h66; 3'd3:font_row=8'h3E; 3'd4:font_row=8'h06; 3'd5:font_row=8'h0C; 3'd6:font_row=8'h38; default:font_row=8'h00; endcase
      default: font_row=8'h00;
    endcase
  endfunction

  // ---- 8x8 字母/符号字模（bit7 = 最左列）----
  function automatic logic [7:0] alpha_row(input logic [3:0] code, input logic [2:0] r);
    case (code)
      4'd0: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h7E; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h66; default:alpha_row=8'h00; endcase // A
      4'd1: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h60; 3'd4:alpha_row=8'h60; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // C
      4'd2: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h60; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h7C; 3'd4:alpha_row=8'h60; 3'd5:alpha_row=8'h60; 3'd6:alpha_row=8'h7E; default:alpha_row=8'h00; endcase // E
      4'd3: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h6E; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // G
      4'd4: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h7E; default:alpha_row=8'h00; endcase // I
      4'd5: case (r) 3'd0:alpha_row=8'hC6; 3'd1:alpha_row=8'hEE; 3'd2:alpha_row=8'hFE; 3'd3:alpha_row=8'hD6; 3'd4:alpha_row=8'hC6; 3'd5:alpha_row=8'hC6; 3'd6:alpha_row=8'hC6; default:alpha_row=8'h00; endcase // M
      4'd6: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h66; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // O
      4'd7: case (r) 3'd0:alpha_row=8'h7C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h7C; 3'd4:alpha_row=8'h68; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h66; default:alpha_row=8'h00; endcase // R
      4'd8: case (r) 3'd0:alpha_row=8'h3C; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h60; 3'd3:alpha_row=8'h3C; 3'd4:alpha_row=8'h06; 3'd5:alpha_row=8'h66; 3'd6:alpha_row=8'h3C; default:alpha_row=8'h00; endcase // S
      4'd9: case (r) 3'd0:alpha_row=8'h7E; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // T
      4'd10: case (r) 3'd0:alpha_row=8'h66; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h66; 3'd4:alpha_row=8'h66; 3'd5:alpha_row=8'h3C; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // V
      4'd11: case (r) 3'd0:alpha_row=8'h66; 3'd1:alpha_row=8'h66; 3'd2:alpha_row=8'h66; 3'd3:alpha_row=8'h3C; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // Y
      4'd12: case (r) 3'd0:alpha_row=8'h00; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h00; 3'd4:alpha_row=8'h00; 3'd5:alpha_row=8'h18; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // :
      4'd13: case (r) 3'd0:alpha_row=8'h18; 3'd1:alpha_row=8'h18; 3'd2:alpha_row=8'h18; 3'd3:alpha_row=8'h18; 3'd4:alpha_row=8'h18; 3'd5:alpha_row=8'h00; 3'd6:alpha_row=8'h18; default:alpha_row=8'h00; endcase // !
      default: alpha_row=8'h00;
    endcase
  endfunction

  // ---- 结束画面字符序列（0=VICTORY! 1=SCORE: 2=GAME OVER）----
  function automatic [3:0] word_code(input logic [1:0] w, input int k);
    case (w)
      2'd0: case (k) 0:word_code=4'd10; 1:word_code=4'd4; 2:word_code=4'd1; 3:word_code=4'd9; 4:word_code=4'd6; 5:word_code=4'd7; 6:word_code=4'd11; default:word_code=4'd13; endcase
      2'd1: case (k) 0:word_code=4'd8; 1:word_code=4'd1; 2:word_code=4'd6; 3:word_code=4'd7; 4:word_code=4'd2; 5:word_code=4'd12; default:word_code=4'd14; endcase
      default: case (k) 0:word_code=4'd3; 1:word_code=4'd0; 2:word_code=4'd5; 3:word_code=4'd2; 4:word_code=4'd14; 5:word_code=4'd6; 6:word_code=4'd10; 7:word_code=4'd2; default:word_code=4'd7; endcase
    endcase
  endfunction

  // ---- 外星人（方头三脚，按行分色）----
  logic hit_enemy, eye;
  logic [23:0] enemy_col;
  always_comb begin
    hit_enemy=1'b0; eye=1'b0; enemy_col=24'hFFFFFF;
    for (int r=0;r<FORM_ROWS;r++) for (int c=0;c<FORM_COLS;c++) begin
      automatic int id = r*FORM_COLS+c;
      automatic int ex = enemy_x0 + c*COL_GAP;
      automatic int ey = enemy_y0 + r*ROW_GAP;
      if (enemy_alive[id] && int'(gx)>=ex && int'(gx)<ex+CELL_W && int'(gy)>=ey && int'(gy)<ey+CELL_H) begin
        automatic int lx = int'(gx)-ex;
        automatic int ly = int'(gy)-ey;
        // 主体（方头）+ 三只脚
        if ((lx>=1 && lx<13 && ly>=0 && ly<6) ||
            (ly>=6 && ly<10 && ((lx>=2&&lx<4)||(lx>=6&&lx<8)||(lx>=10&&lx<12)))) begin
          hit_enemy=1'b1;
          enemy_col = (r==FORM_ROWS-1) ? 24'h5EE7FF : (r>=2) ? 24'hFFFFFF : 24'hFFFF00;
          if ((lx>=4 && lx<6 && ly>=2 && ly<5) || (lx>=8 && lx<10 && ly>=2 && ly<5)) eye=1'b1;
        end
      end
    end
  end

  // ---- 玩家炮台（炮管 + 梯形底座）----
  logic hit_player;
  always_comb begin
    hit_player=1'b0;
    if (player_visible) begin
      automatic int dx = int'(gx) - int'(player_x);
      automatic int dy = int'(gy) - (PLAYER_Y-10);
      if ((dy>=0 && dy<=5 && dx>=-1 && dx<=1) ||
          (dy>=5 && dy<10 && dx>=-(3+(dy-5)) && dx<=(3+(dy-5))))
        hit_player=1'b1;
    end
  end

  // ---- 子弹 ----
  logic hit_pb, hit_eb;
  always_comb begin
    hit_pb=1'b0; hit_eb=1'b0;
    for (int i=0;i<PSLOTS;i++)
      if (pb_valid[i] && int'(gx)>=int'(pb_x[9*i +: 9])-1 && int'(gx)<int'(pb_x[9*i +: 9])+1 &&
          int'(gy)>=int'(pb_y[9*i +: 9])-4 && int'(gy)<int'(pb_y[9*i +: 9])+4)
        hit_pb=1'b1;
    for (int i=0;i<ESLOTS;i++)
      if (eb_valid[i] && int'(gx)>=int'(eb_x[9*i +: 9])-1 && int'(gx)<int'(eb_x[9*i +: 9])+1 &&
          int'(gy)>=int'(eb_y[9*i +: 9])-3 && int'(gy)<int'(eb_y[9*i +: 9])+3)
        hit_eb=1'b1;
  end

  // ---- 掩体（位图 1 = 存在）----
  logic hit_bunker;
  always_comb begin
    hit_bunker=1'b0;
    for (int b=0;b<BUNKERS;b++) begin
      if (int'(gx)>=BUNK_X[b] && int'(gx)<BUNK_X[b]+BUNK_W && int'(gy)>=BUNK_Y && int'(gy)<BUNK_Y+BUNK_H) begin
        if (bunker_bits[b*BUNK_W*BUNK_H + (int'(gy)-BUNK_Y)*BUNK_W + (int'(gx)-BUNK_X[b])])
          hit_bunker=1'b1;
      end
    end
  end

  // ---- 神秘飞碟（红色碟形）----
  logic hit_ufo;
  always_comb begin
    hit_ufo=1'b0;
    if (ufo_active) begin
      automatic int lx = int'(gx) - int'(ufo_x);
      automatic int ly = int'(gy) - UFO_Y;
      if ((ly>=2 && ly<6 && lx>=1 && lx<19) ||
          (ly>=0 && ly<2 && lx>=6 && lx<14))
        hit_ufo=1'b1;
    end
  end

  // ---- HUD：生命(左上第一行)、计分(第二行) ----
  logic hud_on;
  always_comb begin
    hud_on=1'b0;
    // 生命：10 显示两位 "10"，9 以下显示单个数字（原位）
    if (lives >= 4'd10) begin
      if (int'(gy)>=0 && int'(gy)<=7 && int'(gx)>=1 && int'(gx)<9)
        if (font_row(4'd1, gy[2:0])[7-(int'(gx)-1)]) hud_on=1'b1;
      if (int'(gy)>=0 && int'(gy)<=7 && int'(gx)>=9 && int'(gx)<17)
        if (font_row(4'd0, gy[2:0])[7-(int'(gx)-9)]) hud_on=1'b1;
    end else begin
      if (int'(gy)>=0 && int'(gy)<=7 && int'(gx)>=1 && int'(gx)<9)
        if (font_row(lives[3:0], gy[2:0])[7-(int'(gx)-1)]) hud_on=1'b1;
    end
    // 计分 4 位 y=8..15
    for (int k=0;k<4;k++) begin
      automatic int dx = 1 + 8*k;
      if (int'(gy)>=8 && int'(gy)<=15 && int'(gx)>=dx && int'(gx)<dx+8) begin
        automatic int div = (k==0)?1000:((k==1)?100:((k==2)?10:1));
        automatic int dd = (int'(score)/div)%10;
        if (font_row(dd[3:0], gy[2:0])[7-(int'(gx)-dx)]) hud_on=1'b1;
      end
    end
  end

  // ---- 结束画面：败=灰 GAME OVER，胜=绿 VICTORY! + SCORE ----
  logic over_on;
  logic [23:0] over_col;
  always_comb begin
    over_on = 1'b0;
    over_col = 24'h808080;
    if (stage_show) begin
      if (stage_blink) begin
        over_col = 24'hFFFF00;
        for (int k=0; k<5; k++) begin
          automatic int cx = int'(gx) - (104 + k*16);
          automatic int cy = int'(gy) - 112;
          if (cx>=0 && cx<16 && cy>=0 && cy<16)
            if (alpha_row((k==0)?4'd8:(k==1)?4'd9:(k==2)?4'd0:(k==3)?4'd3:4'd2, cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
        end
        begin
          automatic int cx = int'(gx) - (104 + 6*16);
          automatic int cy = int'(gy) - 112;
          if (cx>=0 && cx<16 && cy>=0 && cy<16)
            if (font_row((stage+1'b1), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
        end
      end else begin
        over_on = 1'b1;
        over_col = 24'h000000;
      end
    end else if (state == 2'd3) begin
      if (win) begin
        over_col = 24'h00FF00;
        for (int k=0; k<8; k++) begin
          automatic int cx = int'(gx) - (96 + k*16);
          automatic int cy = int'(gy) - 96;
          if (cx>=0 && cx<16 && cy>=0 && cy<16)
            if (alpha_row(word_code(2'd0,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
        end
        for (int k=0; k<7; k++) begin
          automatic int cx = int'(gx) - (80 + k*16);
          automatic int cy = int'(gy) - 112;
          if (cx>=0 && cx<16 && cy>=0 && cy<16)
            if (alpha_row(word_code(2'd1,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
        end
        for (int k=0; k<4; k++) begin
          automatic int cx = int'(gx) - (72 + (7+k)*16);
          automatic int cy = int'(gy) - 112;
          if (cx>=0 && cx<16 && cy>=0 && cy<16) begin
            automatic int div = (k==0)?1000:((k==1)?100:((k==2)?10:1));
            automatic int dd = (int'(score)/div)%10;
            if (font_row(dd[3:0], cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
          end
        end
      end else begin
        for (int k=0; k<9; k++) begin
          automatic int cx = int'(gx) - (88 + k*16);
          automatic int cy = int'(gy) - 112;
          if (cx>=0 && cx<16 && cy>=0 && cy<16)
            if (alpha_row(word_code(2'd2,k), cy[3:1])[7-cx[3:1]]) over_on = 1'b1;
        end
      end
    end
  end

  // ---- 优先级输出 ----
  always_comb begin
    if (over_on)     rgb = over_col;
    else if (hud_on) rgb = 24'hFFFFFF;
    else if (hit_pb) rgb = 24'hFFFFFF;
    else if (hit_eb) rgb = 24'hFFFFFF;
    else if (hit_player) rgb = 24'h00FF00;
    else if (hit_enemy)  rgb = eye ? 24'h000000 : enemy_col;
    else if (hit_bunker) rgb = 24'h00FF00;
    else if (hit_ufo)    rgb = 24'hFF0000;
    else             rgb = 24'h000000;
  end
endmodule
