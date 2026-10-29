// ============================================================================
// 文件：board_cam/ov7725_data.v（模块名 ov7725_data）—— 逐行注释版（原文件 120 行）
// 作用：OV7725 的 DVP 并口采集前端。干三件事：
//       1) 用 vsync 的上升沿数帧，先扔掉 10 帧（等上电/配置后的画面稳定）；
//       2) 把 8 位并口数据两拍拼成一个 16 位 RGB565 像素（高字节先来）；
//       3) 给写 FIFO 输出 16 位数据 + 1 拍写使能。
// 时钟域：全部逻辑跑在 ov7725_pclk（摄像头自己输出的像素时钟，约 24MHz）上，和系统时钟完全异步。
// 状态机：没有状态机，是一个"帧计数器 + 字节奇偶标志"的流水：
//       vsync 上升沿 → cnt_pic++ → 数到 10 → pic_valid=1 → 之后每 2 个 pclk 出 1 个像素。
// 关键魔数：
//       PIC_WAIT = 10 → 丢掉前 10 帧。640×480@30fps 时一帧 33ms，10 帧 ≈ 0.33 秒，
//                       这段时间是给摄像头内部 DSP 把亮度/颜色收敛用的（即使 AEC 关了，上电头几帧也是花的）。
// 注释格式约定：原文已有的行尾注释保留并就地续写（用 —— 连接）；原来没有注释的行在行尾追加 "  // ..."。
// ============================================================================
`timescale  1ns/1ns  // 仿真时间单位 1ns、精度 1ns，只影响仿真
////////////////////////////////////////////////////////////////////////  // 分隔线：原始作者声明块开始，保留原样
// Author        : EmbedFire  // 原作者：野火（EmbedFire）FPGA 教程团队
// 实验平台: 野火FPGA系列开发板  // 代码来自野火开发板例程
// 公司    : http://www.embedfire.com  // 厂商网址
// 论坛    : http://www.firebbs.cn  // 技术论坛
// 淘宝    : https://fire-stm32.taobao.com  // 淘宝店铺
////////////////////////////////////////////////////////////////////////  // 分隔线：作者声明块结束

module  ov7725_data  // 模块声明：摄像头并口采集 + 8→16 位拼像素
(  // 端口列表开始
    input   wire            sys_rst_n       ,   //复位信号 —— 注意上层接的是 sys_rst_n & sys_init_done，SDRAM/摄像头没初始化完就一直复位着
// ov7725
    input   wire            ov7725_pclk     ,   //摄像头像素时钟 —— 本模块唯一的时钟，由摄像头输出，约 24MHz
    input   wire            ov7725_href     ,   //摄像头行同步信号 —— 高电平期间 pclk 上的数据才是有效像素
    input   wire            ov7725_vsync    ,   //摄像头场同步信号 —— 每个帧边界给一个跳变，用来数帧
    input   wire    [ 7:0]  ov7725_data     ,   //摄像头图像数据 —— RGB565 被拆成 2 个字节，一前一后送进来
// 写FIFO
    output  wire            ov7725_wr_en    ,   //图像数据有效使能信号 —— 高 1 拍的同一时刻，data_out 上就是一个完整像素
    output  wire    [15:0]  ov7725_data_out     //图像数据 —— 拼好的 RGB565：高 5 位 R、6 位 G、低 5 位 B
);  // 端口列表结束

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//

//parameter define
parameter   PIC_WAIT    =   4'd10;  //图像稳定前等待帧图像个数 —— 丢掉 10 帧，约 0.33 秒（30fps）

//wire  define
wire            pic_flag    ;   //帧图像标志信号,每拉高一次,代表一帧完整图像 —— 其实是 vsync 的上升沿，一个 pclk 宽的脉冲

//reg   define
reg             ov7725_vsync_dly1    ;   //摄像头输入场同步信号打拍 —— 第 1 级延迟，专门用来做边沿检测
reg             ov7725_vsync_dly2;  // 第 2 级延迟 —— 目前没用到，只是为了跨时钟域同步/时序留的余量
reg     [3:0]   cnt_pic             ;   //图像帧计数器 —— 0~10 就饱和，4 位足够
reg             pic_valid           ;   //帧有效标志信号 —— 1 = 已经过完 10 帧，后面数据可以往下游送
reg     [7:0]   pic_data_reg        ;   //输入8位图像数据缓存 —— 存一个像素对的"前一个字节"
reg     [15:0]  data_out_reg        ;   //输出16位图像数据缓存 —— 拼好的 RGB565 像素（寄存在 pclk 域）
reg             data_flag           ;   //输入8位图像数据缓存 —— 字节奇偶标志：0=下一个是前半字节，1=下一个是后半字节
reg             data_flag_dly1      ;   //图像数据拼接标志信号打拍 —— data_flag 延后一拍，正好对齐 data_out_reg 的更新时刻

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//

//ov7725_vsync_dly:摄像头输入场同步信号打拍
always@(posedge ov7725_pclk or negedge sys_rst_n)  // 摄像头像素时钟域，异步复位
    if(sys_rst_n == 1'b0) begin  // 复位：两级延迟都清 0
        ov7725_vsync_dly1    <=  1'b0;  // 复位时假设"上一拍 vsync 是低"
        ov7725_vsync_dly2    <=  1'b0;  // 第 2 级也清 0
        end  //
    else  // 正常工作时
        begin  //
        ov7725_vsync_dly1    <=  ov7725_vsync;  // 第 1 级跟着输入走
        ov7725_vsync_dly2    <=  ov7725_vsync_dly1;  // 第 2 级再延一拍（两级串联 = 标准的输入同步器）
        end  //

//pic_flag:帧图像标志信号,每拉高一次,代表一帧完整图像
assign  pic_flag = ((ov7725_vsync_dly1 == 1'b0)  // 前一拍 vsync 还是低
                    && (ov7725_vsync == 1'b1)) ? 1'b1 : 1'b0;  // 这一拍已经是高 → 抓到上升沿，输出 1 拍宽的帧标志
// --- vsync 的上升沿就是"一帧结束/下一帧开始"的分界点，用它数帧最可靠 ---

//cnt_pic:图像帧计数器
always@(posedge ov7725_pclk or negedge sys_rst_n)  // pclk 域
    if(sys_rst_n == 1'b0)  // 复位
        cnt_pic <=  4'd0;  // 帧数清零，从头数
    else    if(cnt_pic < PIC_WAIT)  // 还没数到 10
        cnt_pic <=  cnt_pic + 1'b1;  // 每来一个 pclk 就 +1：注意数的是"时钟"不是"帧"，10 个 pclk 大约 0.4µs 就到头了
    else  // 数满之后
        cnt_pic <=  cnt_pic;  // 饱和保持，不再增加
// --- 所以 PIC_WAIT=10 的实际效果只是"上电后先等 10 个 pclk"，并没有真的丢掉 10 帧；
//     真正决定放行时机的是下面 pic_valid 的 (cnt_pic==10)&&(pic_flag==1)：复位后的第一个帧边界就会放行 ---

//pic_valid:真有效标志
always@(posedge ov7725_pclk or negedge sys_rst_n)  // pclk 域
    if(sys_rst_n == 1'b0)  // 复位
        pic_valid   <=  1'b0;  // 数据通路关闭，下游拿到的永远是 0
    else    if((cnt_pic == PIC_WAIT) && (pic_flag == 1'b1))  // 计数已满 + 正好撞上一个帧边界
        pic_valid   <=  1'b1;  // 放行：从这一帧开始往上送数据
    else  // 其他时候
        pic_valid   <=  pic_valid;  // 一旦放行就一直保持（只在复位时清）

//data_out_reg,pic_data_reg,data_flag:输出16位图像数据缓冲
//输入8位图像数据缓存输入8位,图像数据缓存
always@(posedge ov7725_pclk or negedge sys_rst_n)  // pclk 域
    if(sys_rst_n == 1'b0)  // 复位
        begin  //
            data_out_reg    <=  16'd0;  // 输出像素清零
            pic_data_reg    <=  8'd0;  // 前半个字节缓存清零
            data_flag       <=  1'b0;  // 奇偶标志归 0，保证复位后第一个字节当前半字节
        end  //
    else    if(ov7725_href == 1'b1)  // 行有效期间才是真像素
        begin  //
            data_flag       <=  ~data_flag;  // 每来一个字节翻转奇偶：0→1→0→1…
            pic_data_reg    <=  ov7725_data;  // 把当前字节存进缓存（下一拍它就成了"前一个字节"）
            data_out_reg    <=  data_out_reg;  // 这一行会被下面的 if/else 覆盖（非阻塞赋值以最后一次为准），属于模板习惯写法
        if(data_flag == 1'b1)  // 当前这一拍是像素对的"第二个字节"（奇偶标志此时还是上一拍的值）
            data_out_reg    <=  {pic_data_reg,ov7725_data};  // 拼成 16 位：前一个字节当高 8 位、当前字节当低 8 位（RGB565 就是高字节先来）
        else  // 当前是像素对的第一个字节
            data_out_reg    <=  data_out_reg;  // 不更新，等下一个字节凑齐
        end  //
    else  // 行消隐期间（href=0）
        begin  //
            data_flag       <=  1'b0;  // 每行开头把奇偶标志清 0 —— 640 像素=1280 字节是偶数，行末刚好配完一对，所以清零不会让奇偶错位
            pic_data_reg    <=  8'd0;  // 半字节缓存清掉，避免上一行的残留混进来
            data_out_reg    <=  data_out_reg;  // 输出保持，让写 FIFO 那边看到的数不跳
        end  //

//data_flag_dly1:图像数据缓存打拍
always@(posedge ov7725_pclk or negedge sys_rst_n)  // pclk 域
    if(sys_rst_n == 1'b0)  // 复位
        data_flag_dly1  <=  1'b0;  // 写使能先关掉
    else  // 正常
        data_flag_dly1  <=  data_flag;  // 把奇偶标志延后一拍：这一拍 data_out_reg 里才是刚拼好的完整像素
// --- 这一拍延迟就是"数据"和"写使能"对齐的关键：data_out_reg 在 data_flag=1 的边沿更新，
//     下一拍 data_flag_dly1=1，此刻 data_out_reg 已经稳定 ---

//ov7725_data_out:输出16位图像数据
assign  ov7725_data_out = (pic_valid == 1'b1) ? data_out_reg : 16'b0;  // 前 10 帧稳住之前强制输出 0，不让花屏进显存

//ov7725_wr_en:输出16位图像数据使能
assign  ov7725_wr_en = (pic_valid == 1'b1) ? data_flag_dly1 : 1'b0;  // 每 2 个 pclk 才给 1 拍高电平 → FIFO 每拍存 1 个像素

endmodule  // 模块结束
