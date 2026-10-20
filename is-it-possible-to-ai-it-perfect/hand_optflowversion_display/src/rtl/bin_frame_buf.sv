// bin_frame_buf.sv — 1bit 手部掩膜帧缓存（320x240 抽点域，双时钟标准 BRAM 推断）
//   写侧(pclk)：每 2x2 像素抽 1 点，存 skin(1bit)
//   读侧(clk_disp)：按显示坐标读，显示时 2x2 放大
`timescale 1ns/1ps

module bin_frame_buf #(
  parameter int DW = 320,
  parameter int DH = 240
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic        skin,
  input  logic        href,
  input  logic        vsync,
  input  logic        clk_disp,
  input  logic [8:0]  rdx,      // 显示域列 0..319
  input  logic [7:0]  rdy,      // 显示域行 0..239
  output logic        bin_out
);

  // ---- 写侧像素 / 行计数 ----
  logic [11:0] pcnt, rcnt;
  logic href_d, vsync_d;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      pcnt    <= '0;
      rcnt    <= '0;
      href_d  <= 1'b0;
      vsync_d <= 1'b0;
    end else begin
      href_d  <= href;
      vsync_d <= vsync;
      if (vsync & ~vsync_d) begin
        pcnt <= '0;
        rcnt <= '0;
      end else if (href & ~href_d) begin
        pcnt <= '0;
        rcnt <= rcnt + 1'b1;
      end else if (pixel_en) begin
        pcnt <= pcnt + 1'b1;
      end
    end
  end

  // ---- 抽点：只在列、行均为偶数时写入 ----
  wire        samp = pixel_en && (pcnt[0] == 1'b0) && (rcnt[0] == 1'b0);
  wire [8:0]  sx   = pcnt[9:1];
  wire [8:0]  sy   = rcnt[9:1];
  
  // 地址计算：DW=320 = 256 + 64，利用位移更利于时序优化
  wire [16:0] waddr = (sy << 8) + (sy << 6) + sx;
  wire [16:0] raddr = (rdy << 8) + (rdy << 6) + {8'd0, rdx};

  // ---- 标准双口 BRAM（76800 深度 x 1bit 位宽）----
  // 注意中括号位置：变量名右边表示深度阵列
  (* ram_style = "block" *) logic mem [0:DW*DH-1];

  // 写端口：由 pclk 同步写入，不加异步复位
  always_ff @(posedge pclk) begin
    if (samp)
      mem[waddr] <= skin;
  end

  // 读端口：由 clk_disp 同步读出（BRAM 物理读自带 1 拍周期）
  always_ff @(posedge clk_disp) begin
    bin_out <= mem[raddr];
  end

endmodule