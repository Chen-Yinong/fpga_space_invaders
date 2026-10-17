// num_overlay.sv — 把 0..255 的数值用 3 位 8x8 字体叠加到画面上（只做调试显示）
`timescale 1ns/1ps
module num_overlay (
  input  logic [11:0] px, py,        // 显示坐标
  input  logic [11:0] x0, y0,        // 左上角
  input  logic [7:0]  val,
  output logic        on,
  output logic [23:0] rgb
);
  // bit7 = 最左列，7 行高
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

  wire [3:0] d2 = val / 8'd100;                 // 255 -> 2
  wire [3:0] d1 = (val % 8'd100) / 8'd10;
  wire [3:0] d0 = val % 8'd10;

  wire [11:0] dx = px - x0;
  wire [11:0] dy = py - y0;
  wire in_area = (px >= x0) && (px < x0 + 12'd24) && (py >= y0) && (py < y0 + 12'd8);

  logic [3:0] dig;
  always_comb begin
    if      (dx < 12'd8)  dig = d2;
    else if (dx < 12'd16) dig = d1;
    else                  dig = d0;
  end

  wire bit_on = font_row(dig, dy[2:0])[3'd7 - dx[2:0]];
  assign on  = in_area && bit_on;
  assign rgb = 24'hFFFFFF;
endmodule
