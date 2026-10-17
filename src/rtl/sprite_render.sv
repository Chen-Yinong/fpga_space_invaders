// sprite_render.sv — 把游戏状态画成像素（方块精灵 + 数字 HUD）
`timescale 1ns/1ps
module sprite_render #(
  parameter int PSLOTS = 6,
  parameter int ESLOTS = 3,
  parameter int COL_GAP=24, ROW_GAP=20, CELL_W=16, CELL_H=12,
  parameter int FORM_COLS=10, FORM_ROWS=5,
  parameter int PLAYER_Y=220
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
  input  logic [49:0] enemy_alive,
  input  logic [8:0]  enemy_x0,
  input  logic [8:0]  enemy_y0,
  input  logic [15:0] score,
  input  logic [3:0]  lives,
  input  logic [2:0]  wave,
  output logic [23:0] rgb
);
  logic [8:0] gx, gy;
  assign gx = vid_x[9:1];
  assign gy = vid_y[8:1];

  // ---- 8x8 数字字模（bit7 = 最左）----
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

  // ---- 场景元素 ----
  logic hit_enemy; logic [23:0] enemy_col;
  always_comb begin
    hit_enemy=1'b0; enemy_col=24'h00FF66;
    for (int r=0;r<FORM_ROWS;r++)
      for (int c=0;c<FORM_COLS;c++) begin
        automatic int id = r*FORM_COLS+c;
        automatic int ex = enemy_x0 + c*COL_GAP;
        automatic int ey = enemy_y0 + r*ROW_GAP;
        if (enemy_alive[id] && (int'(gx)>=ex) && (int'(gx)<ex+CELL_W) && (int'(gy)>=ey) && (int'(gy)<ey+CELL_H)) begin
          hit_enemy=1'b1;
          enemy_col = (r==0)?24'hFF648C:(r<3)?24'h5EE7FF:24'h7BF7C8;
        end
      end
  end

  logic hit_player;
  always_comb hit_player = player_visible &&
        (int'(gx) >= int'(player_x)-8) && (int'(gx) < int'(player_x)+8) &&
        (int'(gy) >= PLAYER_Y-10) && (int'(gy) < PLAYER_Y);

  logic hit_pb; logic hit_eb;
  always_comb begin
    hit_pb=1'b0; hit_eb=1'b0;
    for (int i=0;i<PSLOTS;i++)
      if (pb_valid[i] && (int'(gx)>=int'(pb_x[9*i +: 9])-2) && (int'(gx)<int'(pb_x[9*i +: 9])+2)
                     && (int'(gy)>=int'(pb_y[9*i +: 9])-4) && (int'(gy)<int'(pb_y[9*i +: 9])+4))
        hit_pb=1'b1;
    for (int i=0;i<ESLOTS;i++)
      if (eb_valid[i] && (int'(gx)>=int'(eb_x[9*i +: 9])-2) && (int'(gx)<int'(eb_x[9*i +: 9])+2)
                     && (int'(gy)>=int'(eb_y[9*i +: 9])-4) && (int'(gy)<int'(eb_y[9*i +: 9])+4))
        hit_eb=1'b1;
  end

  // ---- HUD（顶部 y=1..8）----
  logic hud_on; logic [23:0] hud_col;
  always_comb begin
    hud_on=1'b0; hud_col=24'hFFFFFF;
    // SCORE 6 位 @ x=2..49, y=1
    for (int k=0;k<6;k++) begin
      automatic int dx = 2 + 8*k;
      if ((int'(gy)>=1) && (int'(gy)<=8) && (int'(gx)>=dx) && (int'(gx)<dx+8)) begin
        automatic int dd = (int'(score) / (10**(5-k))) % 10;
        if (font_row(dd[3:0], (int'(gy)-1)) [7-(int'(gx)-dx)] ) begin hud_on=1'b1; hud_col=24'hFFFFFF; end
      end
    end
    // WAVE 2 位 @ x=150..165, y=1
    for (int k=0;k<2;k++) begin
      automatic int dx = 150 + 8*k;
      if ((int'(gy)>=1) && (int'(gy)<=8) && (int'(gx)>=dx) && (int'(gx)<dx+8)) begin
        automatic int dd = (int'(wave) / (10**(1-k))) % 10;
        if (font_row(dd[3:0], (int'(gy)-1)) [7-(int'(gx)-dx)] ) begin hud_on=1'b1; hud_col=24'h5EE7FF; end
      end
    end
    // LIVES 1 位 @ x=300..307, y=1
    if ((int'(gy)>=1) && (int'(gy)<=8) && (int'(gx)>=300) && (int'(gx)<308)) begin
      if (font_row(lives, (int'(gy)-1)) [7-(int'(gx)-300)] ) begin hud_on=1'b1; hud_col=24'h7BF7C8; end
    end
  end

  always_comb begin
    if (hud_on)          rgb = hud_col;
    else if (hit_pb)     rgb = 24'hFFCA62;
    else if (hit_eb)     rgb = 24'hFF4444;
    else if (hit_player) rgb = 24'hF5F7FF;
    else if (hit_enemy)  rgb = enemy_col;
    else                 rgb = 24'h02040D;
  end
endmodule