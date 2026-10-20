// tb_lk_flow.sv — 光流核心自检：平移纹理块，验证块矢量方向
//   帧0：纹理块在处理域 (64..95, 64..95)（10 原始像素棋盘格，周期 20）
//   帧1：同一纹理块右移 4 个处理域像素（8 原始像素）
//   帧2：不动（应无运动）
//   期望：帧1 在块 (4,4)..(6,5) 出现明显正 u（向右），帧2 u≈0。
`timescale 1ns/1ps
module tb_lk_flow;
  reg pclk = 1'b0;
  reg rst_n = 1'b0;
  reg pixel_en = 1'b0;
  reg href = 1'b0;
  reg vsync = 1'b0;
  reg [7:0] cur_gray = 8'd0;

  wire flow_valid;
  wire signed [31:0] flow_u, flow_v;
  wire [31:0] flow_energy;
  wire [4:0] flow_bx;
  wire [3:0] flow_by;

  lk_flow u_dut (
    .pclk(pclk), .rst_n(rst_n), .pixel_en(pixel_en), .cur_gray(cur_gray),
    .href(href), .vsync(vsync),
    .flow_valid(flow_valid), .flow_u(flow_u), .flow_v(flow_v),
    .flow_energy(flow_energy), .flow_bx(flow_bx), .flow_by(flow_by)
  );

  always #20.833 pclk = ~pclk;   // ~24MHz

  integer tpc, trc;
  integer frame_idx;
  integer seen_valid;
  integer pos_count;

  function automatic [7:0] fgray(input integer fr, pc, rc);
    integer x0;
    begin
      x0 = (fr == 0) ? 128 : 136;
      if ((pc >= x0) && (pc < x0 + 64) && (rc >= 138) && (rc < 202))
        fgray = ((((pc - x0) / 10) + ((rc - 138) / 10)) % 2 == 0) ? 8'd255 : 8'd0;
      else
        fgray = 8'd0;
    end
  endfunction

  always @(*) begin
    href     = (tpc < 640) && (trc >= 10) && (trc < 490);
    vsync    = (trc < 10);
    pixel_en = href;
    cur_gray = fgray(frame_idx, tpc, trc);
  end

  always @(posedge pclk) begin
    if (flow_valid) begin
      seen_valid = seen_valid + 1;
      if (seen_valid <= 40)
        $display("t=%0t  flow bx=%0d by=%0d  u=%0d v=%0d  E=%0d",
                 $time, flow_bx, flow_by, $signed(flow_u), $signed(flow_v), flow_energy);
      if (flow_energy > 20000 && $signed(flow_u) > 8000)
        pos_count = pos_count + 1;
    end
  end

  initial begin
    tpc = 0; trc = 0; frame_idx = 0; seen_valid = 0; pos_count = 0;
    repeat (8) @(posedge pclk);
    @(negedge pclk);
    rst_n = 1'b1;

    repeat (3) begin
      for (trc = 0; trc < 500; trc = trc + 1) begin
        for (tpc = 0; tpc < 700; tpc = tpc + 1) begin
          #1;
          @(posedge pclk);
        end
      end
      frame_idx = frame_idx + 1;
    end

    $display("===== SUMMARY: seen_valid=%0d  positive_moving_blocks=%0d =====",
             seen_valid, pos_count);
    if (pos_count > 0)
      $display("PASS: 检测到明显的向右运动矢量簇");
    else
      $display("FAIL: 未检测到预期方向的运动矢量");
    $finish;
  end
endmodule
