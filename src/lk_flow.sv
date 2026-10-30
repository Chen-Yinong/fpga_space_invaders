// lk_flow.sv — Lucas-Kanade 半稠密光流核心（块级）
//
//   处理域：640x480 摄像头每 2x2 抽一点 -> 320x240（与旧 bin_frame_buf 一致）。
//   数据通路：
//     当前灰度 + 上一帧灰度 -> 3x3 时空窗口 -> Ix,Iy,It
//     -> 16x16 块内累加结构张量 A=ΣIx², B=ΣIxIy, C=ΣIy², D=ΣIxIt, E=ΣIyIt
//     -> 块结束压入 FIFO -> 求解引擎用克莱姆法则解出 (u,v)
//          u = (BE - CD) / (AC - B²)
//          v = (BD - AE) / (AC - B²)
//   输出每个块的运动矢量（定点 Q16，单位：处理域像素/帧）。
`timescale 1ns/1ps
module lk_flow #(
  parameter int DW    = 320,   // 处理域宽
  parameter int DH    = 240,   // 处理域高
  parameter int AW    = 17,    // log2 上取整(DW*DH)
  parameter int BLOCK = 16,    // 块边长
  parameter int QF    = 16,    // 定点小数位
  parameter int DET_MIN = 1000000,  // |det| 下限，低于此判为不可信（防孔径退化）
  parameter int GRAD_MIN = 24       // 像素梯度门限：|Ix|+|Iy| 低于此不参与累加
)(
  input  logic        pclk,
  input  logic        rst_n,
  input  logic        pixel_en,   // cam_wr_en：每像素一拍（RGB565 输出有效）
  input  logic [7:0]  cur_gray,
  input  logic        href,
  input  logic        vsync,
  output logic        flow_valid,
  output logic signed [31:0] flow_u,
  output logic signed [31:0] flow_v,
  output logic [31:0] flow_energy,
  output logic [4:0]  flow_bx,
  output logic [3:0]  flow_by
);
  localparam int NBX = DW / BLOCK;   // 20
  localparam int NBY = DH / BLOCK;   // 15
  localparam int FIFO_DEPTH = 16;

  // =========================================================================
  // 1. 处理域坐标计数（2x2 抽点）
  // =========================================================================
  logic [11:0] pcnt, rcnt;
  logic href_d, vsync_d;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      pcnt <= '0; rcnt <= '0; href_d <= 1'b0; vsync_d <= 1'b0;
    end else begin
      href_d  <= href;
      vsync_d <= vsync;
      if (vsync && !vsync_d) begin
        pcnt <= '0;
        rcnt <= '0;
      end else if (href && !href_d) begin
        pcnt <= '0;
        rcnt <= rcnt + 1'b1;
      end else if (pixel_en) begin
        pcnt <= pcnt + 1'b1;
      end
    end
  end

  wire [8:0] sx = pcnt[9:1];
  wire [7:0] sy = rcnt[9:1];
  wire p_en = pixel_en && (pcnt[0] == 1'b0) && (rcnt[0] == 1'b0);

  wire [AW-1:0] waddr = ({9'd0, sy} * 17'd320) + {8'd0, sx};

  // =========================================================================
  // 2. 双缓冲帧缓存：写当前帧灰度，读上一帧同位置灰度（1 拍延迟）
  // =========================================================================
  logic [7:0] prev_gray;
  gray_framebuf #(.DW(DW), .DH(DH), .AW(AW)) u_fbuf (
    .pclk    (pclk),
    .rst_n   (rst_n),
    .vsync   (vsync),
    .wr_en   (p_en),
    .waddr   (waddr),
    .gray_in (cur_gray),
    .raddr   (waddr),
    .gray_out(prev_gray)
  );

  // 当前灰度打 1 拍，与 prev_gray 对齐到同一处理位置
  logic p_en_d;
  logic [7:0] cur_d;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      p_en_d <= 1'b0;
      cur_d  <= 8'd0;
    end else begin
      p_en_d <= p_en;
      cur_d  <= cur_gray;
    end
  end

  // =========================================================================
  // 3. 行缓冲 + 3x3 窗口（当前帧 / 上一帧各 3 行）
  // =========================================================================
  logic [7:0] cur_r1, cur_r2, prev_r1, prev_r2;
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_cur1 (
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(cur_d), .q(cur_r1)
  );
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_cur2 (
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(cur_r1), .q(cur_r2)
  );
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_prev1 (
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(prev_gray), .q(prev_r1)
  );
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_prev2 (
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(prev_r1), .q(prev_r2)
  );

  // 每行 3 拍移位寄存器，构成 3x3 邻域（中心在列 sx-1）
  logic [7:0] c0, c1, c2;      // cur 当前行 y
  logic [7:0] r10, r11, r12;   // cur 上一行 y-1
  logic [7:0] r20, r21, r22;   // cur 上上行 y-2
  logic [7:0] p0, p1, p2;      // prev 当前行 y
  logic [7:0] q10, q11, q12;   // prev 上一行 y-1
  logic [7:0] q20, q21, q22;   // prev 上上行 y-2
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      c0 <= '0; c1 <= '0; c2 <= '0;
      r10 <= '0; r11 <= '0; r12 <= '0;
      r20 <= '0; r21 <= '0; r22 <= '0;
      p0 <= '0; p1 <= '0; p2 <= '0;
      q10 <= '0; q11 <= '0; q12 <= '0;
      q20 <= '0; q21 <= '0; q22 <= '0;
    end else if (p_en_d) begin
      c0 <= cur_d; c1 <= c0; c2 <= c1;
      r10 <= cur_r1; r11 <= r10; r12 <= r11;
      r20 <= cur_r2; r21 <= r20; r22 <= r21;
      p0 <= prev_gray; p1 <= p0; p2 <= p1;
      q10 <= prev_r1; q11 <= q10; q12 <= q11;
      q20 <= prev_r2; q21 <= q20; q22 <= q21;
    end
  end

  // 窗口中心 (sx-1, sy-1)。中心有效要求 sx>=1 且 sy>=1。
  wire win_valid = (sx >= 9'd1) && (sy >= 8'd1);
  wire win_en    = p_en_d && win_valid;

  // I_x = 中心行右-左，I_y = 中心列下-上，I_t = 当前-上一帧
  logic signed [10:0] ix, iy, it;
  assign ix = $signed({3'd0, r10}) - $signed({3'd0, r12});
  assign iy = $signed({3'd0, c1})  - $signed({3'd0, r21});
  assign it = $signed({3'd0, r11}) - $signed({3'd0, q11});

  // 首帧抑制：复位后第一帧 prev 帧缓存尚未写入有效数据，不参与求解，
  // 只用帧计数（vsync 下降沿 = 帧数据真正开始）跳过前两帧的块输出。
  logic [1:0] frame_cnt;
  wire vsync_fall = !vsync && vsync_d;
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      frame_cnt <= 2'd0;
    end else if (vsync_fall) begin
      if (frame_cnt < 2'd3)
        frame_cnt <= frame_cnt + 1'b1;
    end
  end

  // 像素级梯度门限：平坦区 Ix≈Iy≈0，光流除法会放大感光噪声，直接跳过该点
  wire signed [10:0] ix_abs = (ix >= 11'sd0) ? ix : -ix;
  wire signed [10:0] iy_abs = (iy >= 11'sd0) ? iy : -iy;
  wire [11:0] grad = {1'b0, ix_abs} + {1'b0, iy_abs};
  wire grad_ok = (grad >= GRAD_MIN);

  // =========================================================================
  // 4. 块累加结构张量 A,B,C,D,E
  // =========================================================================
  wire signed [21:0] ixix = ix * ix;
  wire signed [21:0] ixiy = ix * iy;
  wire signed [21:0] iyiy = iy * iy;
  wire signed [21:0] ixit = ix * it;
  wire signed [21:0] iyit = iy * it;

  logic [24:0] accA;
  logic [24:0] accC;
  logic signed [25:0] accB, accD, accE;

  wire [8:0] cx = sx - 9'd1;   // 0..318
  wire [7:0] cy = sy - 8'd1;   // 0..238
  wire [4:0] bx = cx[8:4];
  wire [3:0] by = cy[7:4];

  wire sx_end = ((sx[3:0] == 4'd0) && (sx != 9'd0)) || (sx == (DW-1));
  wire sy_end = ((sy[3:0] == 4'd0) && (sy != 8'd0)) || (sy == (DH-1));
  wire block_end = p_en_d && sx_end && sy_end;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      accA <= '0; accB <= '0; accC <= '0; accD <= '0; accE <= '0;
    end else if (block_end) begin
      accA <= '0; accB <= '0; accC <= '0; accD <= '0; accE <= '0;
    end else if (win_en && grad_ok) begin
      accA <= accA + {9'd0, ixix[15:0]};
      accB <= accB + ixiy;
      accC <= accC + {9'd0, iyiy[15:0]};
      accD <= accD + ixit;
      accE <= accE + iyit;
    end
  end

  // =========================================================================
  // 5. 块结果 FIFO
  // =========================================================================
  logic [24:0] fifoA [0:FIFO_DEPTH-1];
  logic [24:0] fifoC [0:FIFO_DEPTH-1];
  logic signed [25:0] fifoB [0:FIFO_DEPTH-1];
  logic signed [25:0] fifoD [0:FIFO_DEPTH-1];
  logic signed [25:0] fifoE [0:FIFO_DEPTH-1];
  logic [4:0]  fifoBX [0:FIFO_DEPTH-1];
  logic [3:0]  fifoBY [0:FIFO_DEPTH-1];

  logic [3:0] wptr, rptr;
  logic [4:0] fcnt;
  wire fifo_empty = (fcnt == 5'd0);
  wire fifo_full  = (fcnt == FIFO_DEPTH);

  logic engine_pop;

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      wptr <= '0; rptr <= '0; fcnt <= '0;
    end else begin
      if (block_end && !fifo_full && (frame_cnt >= 2'd2)) begin
        fifoA[wptr]  <= accA;
        fifoB[wptr]  <= accB;
        fifoC[wptr]  <= accC;
        fifoD[wptr]  <= accD;
        fifoE[wptr]  <= accE;
        fifoBX[wptr] <= bx;
        fifoBY[wptr] <= by;
        wptr <= wptr + 1'b1;
        fcnt <= fcnt + 1'b1;
      end
      if (engine_pop && !fifo_empty) begin
        rptr <= rptr + 1'b1;
        fcnt <= fcnt - 1'b1;
      end
    end
  end

  // =========================================================================
  // 6. 求解引擎：克莱姆法则 + 双流水线除法器（u、v 并行）
  // =========================================================================
  wire [24:0] A_c = fifoA[rptr];
  wire [24:0] C_c = fifoC[rptr];
  wire signed [25:0] B_c = fifoB[rptr];
  wire signed [25:0] D_c = fifoD[rptr];
  wire signed [25:0] E_c = fifoE[rptr];

  wire signed [53:0] det_c  = ($signed({1'b0, A_c}) * $signed({1'b0, C_c}))
                            - ($signed(B_c) * $signed(B_c));
  wire signed [53:0] numu_c = ($signed(B_c) * $signed(E_c))
                            - ($signed({1'b0, C_c}) * $signed(D_c));
  wire signed [53:0] numv_c = ($signed(B_c) * $signed(D_c))
                            - ($signed({1'b0, A_c}) * $signed(E_c));
  wire [31:0] energy_c = {7'd0, A_c} + {7'd0, C_c};
  wire det_ok = (det_c >= DET_MIN) || (det_c <= -DET_MIN);

  typedef enum logic [1:0] {E_IDLE, E_WAIT} e_state_e;
  e_state_e est;
  logic div_start;
  logic signed [53:0] det_l, numu_l, numv_l;
  logic [31:0] energy_l;
  logic [4:0] bx_l;
  logic [3:0] by_l;

  logic div_done_u, div_done_v, dz_u, dz_v;
  logic signed [31:0] qu, qv;

  div_pipe #(.W(54), .QF(QF)) u_div (
    .clk(pclk), .rst_n(rst_n), .start(div_start),
    .num(numu_l), .den(det_l),
    .done(div_done_u), .quot(qu), .div_by_zero(dz_u)
  );
  div_pipe #(.W(54), .QF(QF)) v_div (
    .clk(pclk), .rst_n(rst_n), .start(div_start),
    .num(numv_l), .den(det_l),
    .done(div_done_v), .quot(qv), .div_by_zero(dz_v)
  );

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      est          <= E_IDLE;
      div_start    <= 1'b0;
      engine_pop   <= 1'b0;
      det_l        <= '0;
      numu_l       <= '0;
      numv_l       <= '0;
      energy_l     <= '0;
      bx_l         <= '0;
      by_l         <= '0;
      flow_valid   <= 1'b0;
      flow_u       <= 32'sd0;
      flow_v       <= 32'sd0;
      flow_energy  <= 32'd0;
      flow_bx      <= 5'd0;
      flow_by      <= 4'd0;
    end else begin
      flow_valid <= 1'b0;
      div_start  <= 1'b0;
      engine_pop <= 1'b0;
      case (est)
        E_IDLE: begin
          if (!fifo_empty) begin
            engine_pop <= 1'b1;
            if (det_ok) begin
              det_l     <= det_c;
              numu_l    <= numu_c;
              numv_l    <= numv_c;
              energy_l  <= energy_c;
              bx_l      <= fifoBX[rptr];
              by_l      <= fifoBY[rptr];
              div_start <= 1'b1;
              est       <= E_WAIT;
            end
          end
        end
        E_WAIT: begin
          if (div_done_u && div_done_v) begin
            flow_valid  <= ~(dz_u || dz_v);
            flow_u      <= qu;
            flow_v      <= qv;
            flow_energy <= energy_l;
            flow_bx     <= bx_l;
            flow_by     <= by_l;
            est         <= E_IDLE;
          end
        end
      endcase
    end
  end
endmodule
