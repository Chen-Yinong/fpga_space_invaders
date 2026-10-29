// ============================================================================
// lk_flow.sv —— 逐行注释版（源文件 333 行，本文件 = 头部框 + 333 行原样源码）
// 做法：源文件每一行原封不动保留在行首，行尾加 "// 中文说明"。
// 可以并排对照原文件看：原文件每一行都原样出现在本文件中（顺序一致），
// 本文件只是多了顶部说明框（15 行）和少数分节注释行，所以原文件第 N 行 = 本文件第 N+15 行。
//
// 一句话：用 Lucas-Kanade 算法算出画面被分成 20×15=300 个 16×16 小方块后，
//         每一块往哪个方向移动了多少像素/帧。
// 数据流：
//   640×480 RGB → 2×2 抽点成 320×240 → 转灰度 Y
//   → 当前帧灰度 vs 上一帧灰度（gray_framebuf 存上一帧）
//   → 3×3 邻域算 Ix(横梯度) Iy(纵梯度) It(时间差)
//   → 每个 16×16 块里把 Ix²、IxIy、Iy²、IxIt、IyIt 累加起来（记作 A B C D E）
//   → 一个块累加完 → 塞进 FIFO → 求解引擎用克莱姆法则解二元一次方程组
//   → 输出 u（横向位移）、v（纵向位移），单位是"处理域像素/帧"，Q16 定点
// ============================================================================
// lk_flow.sv — Lucas-Kanade 半稠密光流核心（块级）                            // 标题：块级（不是逐像素）LK 光流
//                                                                         // 空注释行（原文件续行说明）
//   处理域：640x480 摄像头每 2x2 抽一点 -> 320x240（与旧 bin_frame_buf 一致）。 // 说明：先在处理域降采样，省一半像素
//   数据通路：                                                              // 说明：下面 5 行是数据通路概要
//     当前灰度 + 上一帧灰度 -> 3x3 时空窗口 -> Ix,Iy,It                    // 说明：3×3 邻域求三个方向的差分
//     -> 16x16 块内累加结构张量 A=ΣIx², B=ΣIxIy, C=ΣIy², D=ΣIxIt, E=ΣIyIt   // 说明：这 5 个和就是最小二乘的全部材料
//     -> 块结束压入 FIFO -> 求解引擎用克莱姆法则解出 (u,v)                  // 说明：逐块串行求解，省乘法器
//          u = (BE - CD) / (AC - B²)                                       // 说明：u 的闭式解
//          v = (BD - AE) / (AC - B²)                                       // 说明：v 的闭式解
//   输出每个块的运动矢量（定点 Q16，单位：处理域像素/帧）。                   // 说明：输出单位与格式
`timescale 1ns/1ps                                                      // 仿真时间单位/精度
module lk_flow #(                                                      // 模块声明 + 参数表
  parameter int DW    = 320,   // 处理域宽                              // 参数：处理域宽 320
  parameter int DH    = 240,   // 处理域高                              // 参数：处理域高 240
  parameter int AW    = 17,    // log2 上取整(DW*DH)                    // 参数：帧缓存地址位宽（320×240=76800 → 17 位）
  parameter int BLOCK = 16,    // 块边长                                // 参数：每个方块 16×16 像素
  parameter int QF    = 16,    // 定点小数位                            // 参数：结果保留 16 位小数（Q16）
  parameter int DET_MIN = 1000000,  // |det| 下限，低于此判为不可信（防孔径退化）  // 参数：行列式太小说明这块没纹理，解出来是噪声
  parameter int GRAD_MIN = 24       // 像素梯度门限：|Ix|+|Iy| 低于此不参与累加   // 参数：梯度太小（纯色区）的像素直接跳过
)(                                                                      // 端口表开始
  input  logic        pclk,                                             // 输入：像素时钟（一切都在这个时钟下）
  input  logic        rst_n,                                            // 输入：复位，低有效
  input  logic        pixel_en,   // cam_wr_en：每像素一拍（RGB565 输出有效）      // 输入：本拍有一个有效像素
  input  logic [7:0]  cur_gray,                                         // 输入：当前帧这个像素的灰度值
  input  logic        href,                                             // 输入：行有效（图像数据期间为 1）
  input  logic        vsync,                                            // 输入：场同步（用来分帧、清坐标）
  output logic        flow_valid,                                       // 输出：本拍输出的块结果有效
  output logic signed [31:0] flow_u,                                    // 输出：该块横向位移（Q16，正=向右）
  output logic signed [31:0] flow_v,                                    // 输出：该块纵向位移（Q16，正=向下）
  output logic [31:0] flow_energy,                                      // 输出：该块能量（A+C，纹理强度，用来判断可不可信）
  output logic [4:0]  flow_bx,                                          // 输出：该块列号 0..19
  output logic [3:0]  flow_by                                           // 输出：该块行号 0..14
);                                                                      // 端口表结束
  localparam int NBX = DW / BLOCK;   // 20                              // 常量：横向 20 块
  localparam int NBY = DH / BLOCK;   // 15                              // 常量：纵向 15 块
  localparam int FIFO_DEPTH = 16;                                       // 常量：块结果 FIFO 深度（同时最多积压 16 个块）

  // =========================================================================
  // 1. 处理域坐标计数（2x2 抽点）                                          // 第 1 段：产生处理域坐标
  // =========================================================================
  logic [11:0] pcnt, rcnt;                                              // 内部：像素计数、行计数
  logic href_d, vsync_d;                                                // 内部：href/vsync 延迟一拍（找边沿用）
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：坐标计数
    if (!rst_n) begin                                                    //   复位
      pcnt <= '0; rcnt <= '0; href_d <= 1'b0; vsync_d <= 1'b0;           //     全部清零
    end else begin                                                       //   正常
      href_d  <= href;                                                   //     记下上一拍的 href
      vsync_d <= vsync;                                                  //     记下上一拍的 vsync
      if (vsync && !vsync_d) begin                                       //     vsync 上升沿 = 新的一帧
        pcnt <= '0;                                                      //       列计数归零
        rcnt <= '0;                                                      //       行计数归零
      end else if (href && !href_d) begin                                //     href 上升沿 = 新的一行
        pcnt <= '0;                                                      //       列计数归零
        rcnt <= rcnt + 1'b1;                                             //       行计数 +1
      end else if (pixel_en) begin                                       //     有有效像素
        pcnt <= pcnt + 1'b1;                                             //       列计数 +1
      end                                                                //   三分支结束
    end                                                                  //   else 结束
  end                                                                    //   always 结束

  wire [8:0] sx = pcnt[9:1];                                           // 组合：处理域列号 = 原列号/2（这就是 2×2 抽点）
  wire [7:0] sy = rcnt[9:1];                                           // 组合：处理域行号 = 原行号/2
  wire p_en = pixel_en && (pcnt[0] == 1'b0) && (rcnt[0] == 1'b0);      // 组合：只有偶数列且偶数行才处理 → 2×2 抽成一个点

  wire [AW-1:0] waddr = ({9'd0, sy} * 17'd320) + {8'd0, sx};           // 组合：线性地址 = 行×320 + 列

  // =========================================================================
  // 2. 双缓冲帧缓存：写当前帧灰度，读上一帧同位置灰度（1 拍延迟）            // 第 2 段：拿到"上一帧同一个位置"的灰度
  // =========================================================================
  logic [7:0] prev_gray;                                                // 内部：上一帧同一位置的灰度
  gray_framebuf #(.DW(DW), .DH(DH), .AW(AW)) u_fbuf (    // 例化双缓冲帧缓存（两片 RAM 轮流做"写当前/读上一帧"）
    .pclk    (pclk),                                                     //   时钟
    .rst_n   (rst_n),                                                    //   复位
    .vsync   (vsync),                                                    //   场同步：每帧切换读写片
    .wr_en   (p_en),                                                     //   处理域每点写一次
    .waddr   (waddr),                                                    //   写地址
    .gray_in (cur_gray),                                                 //   写数据：当前灰度
    .raddr   (waddr),                                                    //   读地址与写地址相同 → 同一位置
    .gray_out(prev_gray)                                                 //   读出：上一帧该位置的灰度
  );                                                                     //   例化结束

  // 当前灰度打 1 拍，与 prev_gray 对齐到同一处理位置                        // 说明：RAM 读有 1 拍延迟，所以当前值也要打一拍才"同时"
  logic p_en_d;                                                         // 内部：p_en 延迟一拍
  logic [7:0] cur_d;                                                    // 内部：当前灰度延迟一拍
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：对齐
    if (!rst_n) begin                                                    //   复位
      p_en_d <= 1'b0;                                                    //     有效信号清零
      cur_d  <= 8'd0;                                                    //     数据清零
    end else begin                                                       //   正常
      p_en_d <= p_en;                                                    //     打一拍
      cur_d  <= cur_gray;                                                //     打一拍
    end                                                                  //   else 结束
  end                                                                    //   always 结束

  // =========================================================================
  // 3. 行缓冲 + 3x3 窗口（当前帧 / 上一帧各 3 行）                          // 第 3 段：搭出 3×3 的时空立方体
  // =========================================================================
  logic [7:0] cur_r1, cur_r2, prev_r1, prev_r2;                          // 内部：当前帧前 1 行/前 2 行、上一帧前 1 行/前 2 行
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_cur1 (                            // 例化行缓冲 1：把当前行延迟一整行
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(cur_d), .q(cur_r1)        //   时钟/复位/使能/输入/输出（输出=y-1 行）
  );                                                                     //   例化结束
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_cur2 (                            // 例化行缓冲 2：再延迟一行
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(cur_r1), .q(cur_r2)       //   输出 = y-2 行
  );                                                                     //   例化结束
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_prev1 (                           // 例化行缓冲 3：上一帧的 y-1 行
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(prev_gray), .q(prev_r1)   //   输入上一帧当前行
  );                                                                     //   例化结束
  flow_linebuf #(.DEPTH(DW), .W(8)) lb_prev2 (                           // 例化行缓冲 4：上一帧的 y-2 行
    .clk(pclk), .rst_n(rst_n), .en(p_en_d), .d(prev_r1), .q(prev_r2)     //   输入上一帧 y-1 行
  );                                                                     //   例化结束

  // 每行 3 拍移位寄存器，构成 3x3 邻域（中心在列 sx-1）                     // 说明：每行再横向移 3 个像素，凑成 3×3
  logic [7:0] c0, c1, c2;      // cur 当前行 y                              // 内部：当前帧第 y 行的 3 个像素（x, x-1, x-2）
  logic [7:0] r10, r11, r12;   // cur 上一行 y-1                            // 内部：当前帧第 y-1 行 3 个像素
  logic [7:0] r20, r21, r22;   // cur 上上行 y-2                            // 内部：当前帧第 y-2 行 3 个像素
  logic [7:0] p0, p1, p2;      // prev 当前行 y                             // 内部：上一帧第 y 行 3 个像素
  logic [7:0] q10, q11, q12;   // prev 上一行 y-1                           // 内部：上一帧第 y-1 行 3 个像素
  logic [7:0] q20, q21, q22;   // prev 上上行 y-2                           // 内部：上一帧第 y-2 行 3 个像素
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：横向移位
    if (!rst_n) begin                                                    //   复位：全部清零
      c0 <= '0; c1 <= '0; c2 <= '0;                                      //     当前行清零
      r10 <= '0; r11 <= '0; r12 <= '0;                                   //     y-1 行清零
      r20 <= '0; r21 <= '0; r22 <= '0;                                   //     y-2 行清零
      p0 <= '0; p1 <= '0; p2 <= '0;                                      //     上一帧当前行清零
      q10 <= '0; q11 <= '0; q12 <= '0;                                   //     上一帧 y-1 行清零
      q20 <= '0; q21 <= '0; q22 <= '0;                                   //     上一帧 y-2 行清零
    end else if (p_en_d) begin                                           //   每个处理点
      c0 <= cur_d; c1 <= c0; c2 <= c1;                                   //     当前行右移：新值进 c0，旧值推到 c1、c2
      r10 <= cur_r1; r11 <= r10; r12 <= r11;                             //     y-1 行右移
      r20 <= cur_r2; r21 <= r20; r22 <= r21;                             //     y-2 行右移
      p0 <= prev_gray; p1 <= p0; p2 <= p1;                               //     上一帧当前行右移
      q10 <= prev_r1; q11 <= q10; q12 <= q11;                            //     上一帧 y-1 行右移
      q20 <= prev_r2; q21 <= q20; q22 <= q21;                            //     上一帧 y-2 行右移
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  // 窗口中心 (sx-1, sy-1)。中心有效要求 sx>=1 且 sy>=1。                    // 说明：图像最左/最上一列没有左邻居/上邻居，不算
  wire win_valid = (sx >= 9'd1) && (sy >= 8'd1);                        // 组合：窗口中心是否合法
  wire win_en    = p_en_d && win_valid;                                 // 组合：本拍是否有一个合法的窗口

  // I_x = 中心行右-左，I_y = 中心列下-上，I_t = 当前-上一帧                // 说明：最简单的一阶差分（等价于 [-1 0 1] 卷积核）
  logic signed [10:0] ix, iy, it;                                        // 内部：横梯度、纵梯度、时间差
  assign ix = $signed({3'd0, r10}) - $signed({3'd0, r12});               // 组合：Ix = 中心行 右邻 - 左邻
  assign iy = $signed({3'd0, c1})  - $signed({3'd0, r21});               // 组合：Iy = 中心列 下邻 - 上邻
  assign it = $signed({3'd0, r11}) - $signed({3'd0, q11});               // 组合：It = 当前帧中心 - 上一帧中心（这就是"运动"的来源）

  // 首帧抑制：复位后第一帧 prev 帧缓存尚未写入有效数据，不参与求解，         // 说明：为什么要有 frame_cnt
  // 只用帧计数（vsync 下降沿 = 帧数据真正开始）跳过前两帧的块输出。          //      刚上电时"上一帧"是空的，算出来的 It 全是假的
  logic [1:0] frame_cnt;                                                 // 内部：帧计数器 0..3
  wire vsync_fall = !vsync && vsync_d;                                   // 组合：vsync 下降沿 = 一帧数据开始
  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：帧计数
    if (!rst_n) begin                                                    //   复位
      frame_cnt <= 2'd0;                                                 //     计 0
    end else if (vsync_fall) begin                                       //   每来一帧
      if (frame_cnt < 2'd3)                                              //     最多数到 3
        frame_cnt <= frame_cnt + 1'b1;                                   //       加 1
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  // 像素级梯度门限：平坦区 Ix≈Iy≈0，光流除法会放大感光噪声，直接跳过该点     // 说明：噪声闸门
  wire signed [10:0] ix_abs = (ix >= 11'sd0) ? ix : -ix;                 // 组合：Ix 的绝对值
  wire signed [10:0] iy_abs = (iy >= 11'sd0) ? iy : -iy;                 // 组合：Iy 的绝对值
  wire [11:0] grad = {1'b0, ix_abs} + {1'b0, iy_abs};                    // 组合：梯度幅值 = |Ix|+|Iy|
  wire grad_ok = (grad >= GRAD_MIN);                                     // 组合：梯度够大才算有效点

  // =========================================================================
  // 4. 块累加结构张量 A,B,C,D,E                                            // 第 4 段：把 256 个像素的方程"加起来"
  // =========================================================================
  wire signed [21:0] ixix = ix * ix;                                     // 组合：Ix²（11×11 → 22 位）
  wire signed [21:0] ixiy = ix * iy;                                     // 组合：IxIy
  wire signed [21:0] iyiy = iy * iy;                                     // 组合：Iy²
  wire signed [21:0] ixit = ix * it;                                     // 组合：IxIt
  wire signed [21:0] iyit = iy * it;                                     // 组合：IyIt

  logic [24:0] accA;                                                     // 内部：ΣIx²（25 位，防溢出）
  logic [24:0] accC;                                                     // 内部：ΣIy²
  logic signed [25:0] accB, accD, accE;                                  // 内部：ΣIxIy、ΣIxIt、ΣIyIt（有符号，可能为负）

  wire [8:0] cx = sx - 9'd1;   // 0..318                                  // 组合：窗口中心列
  wire [7:0] cy = sy - 8'd1;   // 0..238                                  // 组合：窗口中心行
  wire [4:0] bx = cx[8:4];                                               // 组合：属于第几块 → 列号 = x/16
  wire [3:0] by = cy[7:4];                                               // 组合：行号 = y/16

  wire sx_end = ((sx[3:0] == 4'd0) && (sx != 9'd0)) || (sx == (DW-1));   // 组合：本拍是不是一行中"块的最后一列"（x%16==0，或到达图像右边界）
  wire sy_end = ((sy[3:0] == 4'd0) && (sy != 8'd0)) || (sy == (DH-1));   // 组合：是不是"块的最后一行"
  wire block_end = p_en_d && sx_end && sy_end;                           // 组合：块最后的那个像素到达 = 一个块累加完成

  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：累加器
    if (!rst_n) begin                                                    //   复位
      accA <= '0; accB <= '0; accC <= '0; accD <= '0; accE <= '0;         //     五个累加器清零
    end else if (block_end) begin                                        //   一个块结束
      accA <= '0; accB <= '0; accC <= '0; accD <= '0; accE <= '0;         //     清零，准备累加下一块
    end else if (win_en && grad_ok) begin                                //   有效窗口 且 梯度够大
      accA <= accA + {9'd0, ixix[15:0]};                                 //     A += Ix²（截到 16 位，省位宽）
      accB <= accB + ixiy;                                               //     B += IxIy
      accC <= accC + {9'd0, iyiy[15:0]};                                 //     C += Iy²
      accD <= accD + ixit;                                               //     D += IxIt
      accE <= accE + iyit;                                               //     E += IyIt
    end                                                                  //   if 结束
  end                                                                    //   always 结束

  // =========================================================================
  // 5. 块结果 FIFO                                                          // 第 5 段：块结果排队，等求解引擎慢慢算
  // =========================================================================
  logic [24:0] fifoA [0:FIFO_DEPTH-1];                                   // 存储：A 的队列
  logic [24:0] fifoC [0:FIFO_DEPTH-1];                                   // 存储：C 的队列
  logic signed [25:0] fifoB [0:FIFO_DEPTH-1];                            // 存储：B 的队列
  logic signed [25:0] fifoD [0:FIFO_DEPTH-1];                            // 存储：D 的队列
  logic signed [25:0] fifoE [0:FIFO_DEPTH-1];                            // 存储：E 的队列
  logic [4:0]  fifoBX [0:FIFO_DEPTH-1];                                  // 存储：块列号
  logic [3:0]  fifoBY [0:FIFO_DEPTH-1];                                  // 存储：块行号

  logic [3:0] wptr, rptr;                                                // 内部：写指针、读指针（深度 16 用 4 位）
  logic [4:0] fcnt;                                                      // 内部：FIFO 里的块数
  wire fifo_empty = (fcnt == 5'd0);                                      // 组合：空
  wire fifo_full  = (fcnt == FIFO_DEPTH);                                // 组合：满

  logic engine_pop;                                                      // 内部：求解引擎这一拍取走一个（下面状态机驱动）

  always_ff @(posedge pclk or negedge rst_n) begin                       // 时序逻辑：FIFO 读写
    if (!rst_n) begin                                                    //   复位
      wptr <= '0; rptr <= '0; fcnt <= '0;                                //     指针和计数清零
    end else begin                                                       //   正常
      if (block_end && !fifo_full && (frame_cnt >= 2'd2)) begin          //     块完成、队列没满、且已跳过前两帧
        fifoA[wptr]  <= accA;                                            //       写入 A
        fifoB[wptr]  <= accB;                                            //       写入 B
        fifoC[wptr]  <= accC;                                            //       写入 C
        fifoD[wptr]  <= accD;                                            //       写入 D
        fifoE[wptr]  <= accE;                                            //       写入 E
        fifoBX[wptr] <= bx;                                              //       写入列号
        fifoBY[wptr] <= by;                                              //       写入行号
        wptr <= wptr + 1'b1;                                             //       写指针 +1（4 位自然回绕）
        fcnt <= fcnt + 1'b1;                                             //       计数 +1
      end                                                                //     if 结束
      if (engine_pop && !fifo_empty) begin                               //     引擎取走一个
        rptr <= rptr + 1'b1;                                             //       读指针 +1
        fcnt <= fcnt - 1'b1;                                             //       计数 -1
      end                                                                //     if 结束
    end                                                                  //   else 结束
  end                                                                    //   always 结束

  // =========================================================================
  // 6. 求解引擎：克莱姆法则 + 双流水线除法器（u、v 并行）                     // 第 6 段：真正解方程
  // =========================================================================
  wire [24:0] A_c = fifoA[rptr];                                         // 组合：取出队首的 A
  wire [24:0] C_c = fifoC[rptr];                                         // 组合：取出队首的 C
  wire signed [25:0] B_c = fifoB[rptr];                                  // 组合：取出队首的 B
  wire signed [25:0] D_c = fifoD[rptr];                                  // 组合：取出队首的 D
  wire signed [25:0] E_c = fifoE[rptr];                                  // 组合：取出队首的 E

  wire signed [53:0] det_c  = ($signed({1'b0, A_c}) * $signed({1'b0, C_c}))  // 组合：行列式 det = AC - B²
                            - ($signed(B_c) * $signed(B_c));               //   第二项
  wire signed [53:0] numu_c = ($signed(B_c) * $signed(E_c))               // 组合：u 的分子 = BE - CD
                            - ($signed({1'b0, C_c}) * $signed(D_c));       //   第二项
  wire signed [53:0] numv_c = ($signed(B_c) * $signed(D_c))               // 组合：v 的分子 = BD - AE
                            - ($signed({1'b0, A_c}) * $signed(E_c));       //   第二项
  wire [31:0] energy_c = {7'd0, A_c} + {7'd0, C_c};                       // 组合：能量 = A+C（纹理总强度）
  wire det_ok = (det_c >= DET_MIN) || (det_c <= -DET_MIN);                // 组合：行列式绝对值够大 → 这块可信

  typedef enum logic [1:0] {E_IDLE, E_WAIT} e_state_e;                    // 类型：两状态枚举（空闲、等除法器）
  e_state_e est;                                                          // 内部：当前求解状态
  logic div_start;                                                        // 内部：启动除法器
  logic signed [53:0] det_l, numu_l, numv_l;                              // 内部：锁存的分子分母
  logic [31:0] energy_l;                                                  // 内部：锁存的能量
  logic [4:0] bx_l;                                                       // 内部：锁存的列号
  logic [3:0] by_l;                                                       // 内部：锁存的行号

  logic div_done_u, div_done_v, dz_u, dz_v;                               // 内部：两个除法器的完成标志、除零标志
  logic signed [31:0] qu, qv;                                             // 内部：两个除法器的商（就是 u 和 v）

  div_pipe #(.W(54), .QF(QF)) u_div (                                     // 例化除法器 1：算 u
    .clk(pclk), .rst_n(rst_n), .start(div_start),                         //   时钟/复位/启动
    .num(numu_l), .den(det_l),                                            //   分子/分母
    .done(div_done_u), .quot(qu), .div_by_zero(dz_u)                      //   完成/商/除零
  );                                                                      //   例化结束
  div_pipe #(.W(54), .QF(QF)) v_div (                                     // 例化除法器 2：算 v（与 u 完全并行）
    .clk(pclk), .rst_n(rst_n), .start(div_start),                         //   时钟/复位/启动（同一个 start）
    .num(numv_l), .den(det_l),                                            //   分子/分母（分母相同，省一次计算）
    .done(div_done_v), .quot(qv), .div_by_zero(dz_v)                      //   完成/商/除零
  );                                                                      //   例化结束

  always_ff @(posedge pclk or negedge rst_n) begin                         // 时序逻辑：求解状态机
    if (!rst_n) begin                                                     //   复位：全部归零
      est          <= E_IDLE;                                             //     回到空闲
      div_start    <= 1'b0;                                               //     不启动除法
      engine_pop   <= 1'b0;                                               //     不弹 FIFO
      det_l        <= '0;                                                 //     锁存值清零
      numu_l       <= '0;                                                 //       ：
      numv_l       <= '0;                                                 //       ：
      energy_l     <= '0;                                                 //       ：
      bx_l         <= '0;                                                 //       ：
      by_l         <= '0;                                                 //       ：
      flow_valid   <= 1'b0;                                               //     输出无效
      flow_u       <= 32'sd0;                                             //     u 清 0
      flow_v       <= 32'sd0;                                             //     v 清 0
      flow_energy  <= 32'd0;                                              //     能量清 0
      flow_bx      <= 5'd0;                                               //     列号清 0
      flow_by      <= 4'd0;                                               //     行号清 0
    end else begin                                                        //   正常
      flow_valid <= 1'b0;                                                 //     默认本拍无输出（下面只在算出结果时拉高）
      div_start  <= 1'b0;                                                 //     默认不启动除法（打一拍脉冲）
      engine_pop <= 1'b0;                                                 //     默认不弹 FIFO
      case (est)                                                          //     状态机
        E_IDLE: begin                                                     //       空闲：看队列有没有待解块
          if (!fifo_empty) begin                                          //         有块
            engine_pop <= 1'b1;                                           //           把它从 FIFO 取走
            if (det_ok) begin                                             //           行列式够大 → 值得算
              det_l     <= det_c;                                         //             锁存分母
              numu_l    <= numu_c;                                        //             锁存 u 的分子
              numv_l    <= numv_c;                                        //             锁存 v 的分子
              energy_l  <= energy_c;                                      //             锁存能量
              bx_l      <= fifoBX[rptr];                                  //             锁存列号
              by_l      <= fifoBY[rptr];                                  //             锁存行号
              div_start <= 1'b1;                                          //             启动两个除法器
              est       <= E_WAIT;                                        //             进入等待状态
            end                                                           //           if 结束（det 太小就丢弃这块，不输出）
          end                                                             //         if 结束
        end                                                               //       分支结束
        E_WAIT: begin                                                     //       等待除法器算完
          if (div_done_u && div_done_v) begin                             //         两个都算完
            flow_valid  <= ~(dz_u || dz_v);                               //           只要不是除零，就输出有效
            flow_u      <= qu;                                            //           输出 u
            flow_v      <= qv;                                            //           输出 v
            flow_energy <= energy_l;                                      //           输出能量
            flow_bx     <= bx_l;                                          //           输出列号
            flow_by     <= by_l;                                          //           输出行号
            est         <= E_IDLE;                                        //           回到空闲，解下一个块
          end                                                             //         if 结束
        end                                                               //       分支结束
      endcase                                                             //     状态机结束
    end                                                                   //   else 结束
  end                                                                     //   always 结束
endmodule                                                                // 模块结束
