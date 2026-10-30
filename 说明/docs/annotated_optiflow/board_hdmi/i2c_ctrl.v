// ============================================================================
// 文件：board_hdmi/i2c_ctrl.v（模块名 i2c_ctrl）—— 逐行注释版（原文件 348 行）
// 作用：通用位级 I2C 主机，用来配置 HDMI 发送芯片（板上 SiI9134）的内部寄存器。
//       一次 i2c_start = 一次完整传输：
//         写：START → 器件地址+W → 寄存器地址(8/16 位) → 数据字节 → STOP
//         读：START → 器件地址+W → 寄存器地址 → 重复START → 器件地址+R → 读 1 字节 → NACK → STOP
// 和摄像头版（board_cam/i2c_ctrl.v，模块名 cam_i2c_ctrl）的区别：
//       1) 器件地址不是参数，而是一个 8 位输入端口 device_addr，运行时可变（因为 HDMI 芯片有三个 I2C 从地址）；
//       2) 端口 device_addr 只取 [7:1] 当 7 位地址用，最低位丢弃（写方向由状态机自己发 0/1）；
//       3) 其余时序/状态机完全一样。
// 状态机：共 16 个状态（IDLE / START_1 / SEND_D_ADDR / ACK_1 / SEND_B_ADDR_H / ACK_2 /
//         SEND_B_ADDR_L / ACK_3 / WR_DATA / ACK_4 / START_2 / SEND_RD_ADDR / ACK_5 /
//         RD_DATA / N_ACK / STOP）。
// 关键时序（默认参数 SYS_CLK_FREQ=50MHz、SCL_FREQ=250kHz；实际 hdmi_i2c.v 里传的是 25MHz）：
//       CNT_CLK_MAX = (SYS_CLK_FREQ/SCL_FREQ)>>3 = 200>>3 = 25
//       → i2c_clk 每 25 个 sys_clk 翻转一次 → i2c_clk = 50M/(2×25) = 1MHz（周期 1µs）
//       → 每个 SCL 位占 4 个 i2c_clk → SCL = 250kHz（周期 4µs，高低各 2µs）
//       按 25MHz 算：CNT_CLK_MAX=12 → i2c_clk≈1.042MHz → SCL≈260kHz。
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

module  i2c_ctrl  // 模块声明：通用 I2C 主机（HDMI 版；摄像头版同名模块叫 cam_i2c_ctrl）
#(  // 参数列表开始
    parameter   SYS_CLK_FREQ    =   26'd50_000_000  ,   //输入系统时钟频率 —— 26 位宽存 50MHz，只用来算 cnt_clk 的分频上限
    parameter   SCL_FREQ        =   18'd250_000         //i2c设备scl时钟频率 —— 目标 SCL=250kHz（I2C 快速模式上限 400kHz，留余量）
)  // 参数列表结束
(  // 端口列表开始
    input   wire            sys_clk     ,   //输入系统时钟,50MHz —— 本模块最高频时钟，分频出 i2c_clk
    input   wire            sys_rst_n   ,   //输入复位信号,低电平有效 —— 异步复位，复位后总线回到空闲
    input   wire            wr_en       ,   //输入写使能信号 —— 1 表示这次访问是"写寄存器"
    input   wire            rd_en       ,   //输入读使能信号 —— 1 表示这次访问是"读寄存器"（wr_en=0 时才看它）
    input   wire            i2c_start   ,   //输入i2c触发信号 —— 拉高一个周期就启动一次完整传输
    input   wire            addr_num    ,   //输入i2c字节地址字节数 —— 1=发 16 位寄存器地址(先高后低)，0=只发低 8 位
    input   wire    [7:0]   device_addr ,   // 器件地址（8 位）—— 比摄像头版多出来的端口：HDMI 芯片有 0x72/0x7A/0x60 多段地址，只能运行时给
    input   wire    [15:0]  byte_addr   ,   //输入i2c字节地址 —— 要访问的寄存器地址
    input   wire    [7:0]   wr_data     ,   //输入i2c设备数据 —— 要写进寄存器的 8 位值

    output  reg             i2c_clk     ,   //i2c驱动时钟 —— 内部状态机的时钟（1MHz 左右），还要送给 hdmi_cfg 当 sys_clk
    output  reg             i2c_end     ,   //i2c一次读/写操作完成 —— 一个 i2c_clk 宽的脉冲
    output  reg     [7:0]   rd_data     ,   //输出i2c设备读取数据 —— 读操作结束时整字节搬出来
    output  reg             i2c_scl     ,   //输出至i2c设备的串行时钟信号scl —— 组合逻辑按状态产生
    inout   wire            i2c_sda         //输出至i2c设备的串行数据信号sda —— 双向：本模块驱动 or 释放成高阻
);  // 端口列表结束

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// parameter define
parameter   CNT_CLK_MAX     =   (SYS_CLK_FREQ/SCL_FREQ) >> 2'd3   ;   //cnt_clk计数器计数最大值 —— 50M/250k=200 再右移 3 位(÷8)得 25；÷8 是因为一个 SCL 位要 4 个 i2c_clk，而 i2c_clk 一个周期又要数 2 次

parameter   CNT_START_MAX   =   8'd100; //cnt_start计数器计数最大值 —— 上电延时的预留参数，本文件里没有任何逻辑用到它（残留）

parameter   IDLE            =   4'd00,  //初始状态 —— 总线空闲：SCL=1、SDA=1，只等 i2c_start
            START_1         =   4'd01,  //开始状态1 —— 在 SCL 高电平期间把 SDA 由 1 拉成 0，产生 START 条件
            SEND_D_ADDR     =   4'd02,  //设备地址写入状态 + 控制写 —— 先发 7 位器件地址，第 8 位发 0 表示"写"
            ACK_1           =   4'd03,  //应答状态1 —— 释放 SDA，收回从机对器件地址的 ACK
            SEND_B_ADDR_H   =   4'd04,  //字节地址高八位写入状态 —— 只有 addr_num=1（16 位地址）才会经过这里
            ACK_2           =   4'd05,  //应答状态2 —— 收回高字节地址的 ACK
            SEND_B_ADDR_L   =   4'd06,  //字节地址低八位写入状态 —— 发寄存器地址的低 8 位
            ACK_3           =   4'd07,  //应答状态3 —— 收回地址 ACK，然后按 wr_en/rd_en 决定往写还是往读走
            WR_DATA         =   4'd08,  //写数据状态 —— 把 wr_data 高位先出地逐位送到 SDA
            ACK_4           =   4'd09,  //应答状态4 —— 收回写数据的 ACK，之后直接去 STOP
            START_2         =   4'd10,  //开始状态2 —— 读操作前的"重复起始 Sr"
            SEND_RD_ADDR    =   4'd11,  //设备地址写入状态 + 控制读 —— 再发一次器件地址，第 8 位发 1 表示"读"
            ACK_5           =   4'd12,  //应答状态5 —— 收回从机对"读地址"的 ACK
            RD_DATA         =   4'd13,  //读数据状态 —— 逐位把从机送来的数据移进 rd_data_reg
            N_ACK           =   4'd14,  //非应答状态 —— 主机回一个 NACK，表示"不再读了"
            STOP            =   4'd15;  //结束状态 —— 在 SCL 高电平期间把 SDA 由 0 拉成 1，产生 STOP，然后回 IDLE

// wire  define
wire            sda_in          ;   //sda输入数据寄存 —— 映射 SDA 引脚的实际电平，用来读数据/收 ACK
wire            sda_en          ;   //sda数据写入使能信号 —— 1=本模块驱动 SDA，0=释放成高阻让从机驱动
wire    [6:0]   device_addr_i;  // 7 位器件地址 —— 由 8 位端口 device_addr 截掉最低位得到，专门给移位输出用
// reg   define
reg     [7:0]   cnt_clk         ;   //系统时钟计数器,控制生成clk_i2c时钟信号 —— 0~24 循环，数满一次让 i2c_clk 翻一次
reg     [3:0]   state           ;   //状态机状态 —— 16 个状态，4 位刚好装下
reg             cnt_i2c_clk_en  ;   //cnt_i2c_clk计数器使能信号 —— 传输开始置 1，STOP 结束后清 0
reg     [1:0]   cnt_i2c_clk     ;   //clk_i2c时钟计数器,控制生成cnt_bit信号 —— 每位内部数 0~3，2 位自然回绕
reg     [2:0]   cnt_bit         ;   //sda比特计数器 —— 一个字节内数 0~7
reg             ack             ;   //应答信号 —— 缓存从机在 ACK 时隙给出的电平（0 才算有效应答）
reg             i2c_sda_reg     ;   //sda数据缓存 —— 准备输出到 SDA 的位值
reg     [7:0]   rd_data_reg     ;   //自i2c设备读出数据 —— 读操作时的移位寄存器

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//

assign device_addr_i=device_addr[7:1];  // 8 位端口 → 7 位地址：丢掉最低位（最低位是方向位 R/W），I2C 上真正要发的只有高 7 位
// --- 时钟分频级：先把 sys_clk 降成 i2c_clk（1MHz），后面所有位时序都以它为基准 ---
// cnt_clk:系统时钟计数器,控制生成clk_i2c时钟信号
always@(posedge sys_clk or negedge sys_rst_n)  // sys_clk 上升沿工作，复位异步清零
    if(sys_rst_n == 1'b0)  // 复位有效
        cnt_clk <=  8'd0;  // 分频计数器清零
    else    if(cnt_clk == CNT_CLK_MAX - 1'b1)  // 数到 24（50MHz 下 25 个时钟 = 500ns）
        cnt_clk <=  8'd0;  // 归零，准备下一轮
    else  // 还没数满
        cnt_clk <=  cnt_clk + 1'b1;  // 每个 sys_clk 加 1

// i2c_clk:i2c驱动时钟
always@(posedge sys_clk or negedge sys_rst_n)  // 仍然是 sys_clk 域
    if(sys_rst_n == 1'b0)  // 复位有效
        i2c_clk <=  1'b1;  // 复位给高电平，和"总线空闲 SCL=1"的习惯一致
    else    if(cnt_clk == CNT_CLK_MAX - 1'b1)  // 每 25 个 sys_clk
        i2c_clk <=  ~i2c_clk;  // 翻转一次 → 周期 2×25/50MHz = 1µs，即 1MHz

//--- 下面进入 i2c_clk（1MHz）时钟域，SCL 的位时序都在这里算 ---
// --- 位时序计数链：cnt_i2c_clk_en(总开关) → cnt_i2c_clk(位内 0~3) → cnt_bit(第几位) ---
// cnt_i2c_clk_en:cnt_i2c_clk计数器使能信号
always@(posedge i2c_clk or negedge sys_rst_n)  // 时钟换成了 i2c_clk，时钟域变了
    if(sys_rst_n == 1'b0)  // 复位
        cnt_i2c_clk_en  <=  1'b0;  // 上电不计数，总线安静
    else    if((state == STOP) && (cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))  // STOP 走完 4 个位（cnt_bit 0~3）的最后半位
        cnt_i2c_clk_en  <=  1'b0;  // 关掉位计数器，传完不再空转
    else    if(i2c_start == 1'b1)  // 收到传输触发
        cnt_i2c_clk_en  <=  1'b1;  // 打开位计数器

// cnt_i2c_clk:i2c_clk时钟计数器,控制生成cnt_bit信号
always@(posedge i2c_clk or negedge sys_rst_n)  // i2c_clk 域
    if(sys_rst_n == 1'b0)  // 复位
        cnt_i2c_clk <=  2'd0;  // 位内计数器清零
    else    if(cnt_i2c_clk_en == 1'b1)  // 使能打开才走
        cnt_i2c_clk <=  cnt_i2c_clk + 1'b1;  // 0→1→2→3→0 自然回绕，一个 SCL 位正好 4 拍

// cnt_bit:sda比特计数器
always@(posedge i2c_clk or negedge sys_rst_n)  // i2c_clk 域
    if(sys_rst_n == 1'b0)  // 复位
        cnt_bit <=  3'd0;  // 位数清零
    else    if((state == IDLE) || (state == START_1) || (state == START_2)  // 起始类状态不数位
                || (state == ACK_1) || (state == ACK_2) || (state == ACK_3)  // 应答只占 1 位
                || (state == ACK_4) || (state == ACK_5) || (state == N_ACK))  //
        cnt_bit <=  3'd0;  // 这些状态里位数恒为 0，保证下一个字节从 bit7 重新开始
    else    if((cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3))  // 第 8 位的最后一拍
        cnt_bit <=  3'd0;  // 一个字节发完，回绕
    else    if((cnt_i2c_clk == 2'd3) && (state != IDLE))  // 每个 SCL 位的最后一拍
        cnt_bit <=  cnt_bit + 1'b1;  // 才进位 → 一位占 4 个 i2c_clk（4µs）

// --- 核心状态机：16 个状态，写流程和读流程共用一套 ---
// state:状态机状态跳转
always@(posedge i2c_clk or negedge sys_rst_n)  // 状态机跑在 i2c_clk 域
    if(sys_rst_n == 1'b0)  // 复位
        state   <=  IDLE;  // 回到空闲
    else    case(state)  //--- 16 选 1 的状态跳转表（每个分支都在等某个"半位/整字节"的边界条件） ---
        IDLE:  // 空闲态
            if(i2c_start == 1'b1)  // 上层给了触发脉冲
                state   <=  START_1;  // 去做起始条件
            else  // 没触发
                state   <=  state;  // 原地保持，总线不动
        START_1:  // 起始条件
            if(cnt_i2c_clk == 3)  // 起始条件占满 1 个 SCL 位（4 个 i2c_clk）
                state   <=  SEND_D_ADDR;  // 位时序走完，开始发器件地址
            else  // 还没走完
                state   <=  state;  // 继续等
        SEND_D_ADDR:  // 发"器件地址 + 写位"
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))  // 8 位全部发完的最后一拍
                state   <=  ACK_1;  // 去收应答
            else  // 还在发
                state   <=  state;  // 保持
        ACK_1:  // 收器件地址应答
            if((cnt_i2c_clk == 3) && (ack == 1'b0))  // 时隙结束且从机拉低（ACK 有效）
                begin  // 地址被认了，按地址宽度分岔
                    if(addr_num == 1'b1)  // 要发 16 位寄存器地址
                        state   <=  SEND_B_ADDR_H;  // 先发高字节
                    else  // 8 位寄存器地址（本设计就这种）
                        state   <=  SEND_B_ADDR_L;  // 直接发低字节
                end  //
             else  // 没有应答（从机不在/地址错）
                state   <=  state;  // 卡在 ACK_1，等于传输失败停住（靠软件超时处理）
        SEND_B_ADDR_H:  // 发地址高 8 位
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))  // 8 位发完
                state   <=  ACK_2;  // 去收应答
            else  // 还没发完
                state   <=  state;  // 保持
        ACK_2:  // 收高字节应答
            if((cnt_i2c_clk == 3) && (ack == 1'b0))  // 有应答
                state   <=  SEND_B_ADDR_L;  // 接着发低字节
            else  // 无应答
                state   <=  state;  // 停住
        SEND_B_ADDR_L:  // 发地址低 8 位
            if((cnt_bit == 3'd7) && (cnt_i2c_clk == 3))  // 8 位发完
                state   <=  ACK_3;  // 去收应答
            else  // 还没发完
                state   <=  state;  // 保持
        ACK_3:  // 收地址应答，然后决定读还是写
            if((cnt_i2c_clk == 3) && (ack == 1'b0))  // 地址被确认
                begin  // 按上层命令分岔
                    if(wr_en == 1'b1)  // 写操作
                        state   <=  WR_DATA;  // 直接发数据
                    else    if(rd_en == 1'b1)  // 读操作
                        state   <=  START_2;  // 先来重复起始，把方向切成读
                    else  // 既不读也不写
                        state   <=  state;  // 停住（本设计不会出现）
                end  //
             else  // 无应答
                state   <=  state;  // 停住
        WR_DATA:  // 发 8 位数据
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))  // 发完
                state   <=  ACK_4;  // 收应答
            else  // 还没发完
                state   <=  state;  // 保持
        ACK_4:  // 收写数据应答
            if((cnt_i2c_clk == 3) && (ack == 1'b0))  // 从机确认收到
                state   <=  STOP;  // 收尾
            else  // 无应答
                state   <=  state;  // 停住
        START_2:  // 重复起始（Sr）
            if(cnt_i2c_clk == 3)  // 占满 1 个 SCL 位
                state   <=  SEND_RD_ADDR;  // 去发"器件地址 + 读位"
            else  // 还没走完
                state   <=  state;  // 保持
        SEND_RD_ADDR:  // 发"器件地址 + 读位(1)"
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))  // 8 位发完
                state   <=  ACK_5;  // 收应答
            else  // 还没发完
                state   <=  state;  // 保持
        ACK_5:  // 收读地址应答
            if((cnt_i2c_clk == 3) && (ack == 1'b0))  // 从机应答，准备吐数据
                state   <=  RD_DATA;  // 进入读数据
            else  // 无应答
                state   <=  state;  // 停住
        RD_DATA:  // 读 8 位
            if((cnt_bit == 3'd7) &&(cnt_i2c_clk == 3))  // 读完
                state   <=  N_ACK;  // 回 NACK，表示不再读
            else  // 还没读完
                state   <=  state;  // 保持
        N_ACK:  // 非应答位
            if(cnt_i2c_clk == 3)  // 这个位走完
                state   <=  STOP;  // 去收尾
            else  // 还没走完
                state   <=  state;  // 保持
        STOP:  // 停止条件
            if((cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))  // 只数到 cnt_bit=3：STOP 不需要凑满一个字节，几个 SCL 位就够
                state   <=  IDLE;  // 总线释放，回空闲
            else  // 还没走完
                state   <=  state;  // 保持
        default:    state   <=  IDLE;  // 状态编码异常时兜底回空闲，避免卡死
    endcase

// --- 三个组合输出块：ack 采样（收应答）/ i2c_scl 波形 / i2c_sda_reg 波形 ---
// ack:应答信号
always@(*)  // 纯组合，跟着 state 和 SDA 立即变
    case    (state)  //--- 只有 ACK_x 状态才真的采 SDA，其余状态把 ack 强置 1（"没有应答"）---
        IDLE,START_1,SEND_D_ADDR,SEND_B_ADDR_H,SEND_B_ADDR_L,  // 发数据阶段 SDA 归主机，采不到应答
        WR_DATA,START_2,SEND_RD_ADDR,RD_DATA,N_ACK:  // 读数据/非应答阶段也不需要 ack
            ack <=  1'b1;  // 统一给 1，保持"未确认"语义
        ACK_1,ACK_2,ACK_3,ACK_4,ACK_5:  // 5 个应答时隙
            if(cnt_i2c_clk == 2'd0)  // 只在 SCL 拉低后的第一拍采一次（避开跳变沿）
                ack <=  sda_in;//1'b0;// —— 直接采 SDA：被从机拉低就是 0=ACK 有效（后面那段 1'b0 是调试时强制应答的注释残留）
            else  // 其余时间
                ack <=  ack;  // 锁住采到的值
        default:    ack <=  1'b1;  // 异常状态当作无应答
    endcase

// i2c_scl:输出至i2c设备的串行时钟信号scl
always@(*)  // 组合产生
    case    (state)  //--- SCL 波形定义：250kHz，一个位 4 拍，高 2 拍低 2 拍 ---
        IDLE:  // 空闲
            i2c_scl <=  1'b1;  // SCL 保持高，总线空闲
        START_1:  // 起始条件
            if(cnt_i2c_clk == 2'd3)  // 前 3 拍 SCL 还是高，让 SDA 的 1→0 落在高电平里
                i2c_scl <=  1'b0;  // 第 4 拍才拉低
            else  // 前 3 拍
                i2c_scl <=  1'b1;  // 保持高
        SEND_D_ADDR,ACK_1,SEND_B_ADDR_H,ACK_2,SEND_B_ADDR_L,  // 所有"发数据/收应答/读数据"状态共用同一套位波形
        ACK_3,WR_DATA,ACK_4,START_2,SEND_RD_ADDR,ACK_5,RD_DATA,N_ACK:  //
            if((cnt_i2c_clk == 2'd1) || (cnt_i2c_clk == 2'd2))  // 一个位 4 拍里的中间 2 拍
                i2c_scl <=  1'b1;  // 拉高 → 这 2µs 内数据必须稳定（从机就在这采样）
            else  // 首尾两拍（0 和 3）
                i2c_scl <=  1'b0;  // 拉低 → 主机在这段时间改 SDA
        STOP:  // 停止条件
            if((cnt_bit == 3'd0) &&(cnt_i2c_clk == 2'd0))  // 只在第 1 个位的第 1 拍
                i2c_scl <=  1'b0;  // 拉低一下，让 SDA 先在低电平里变成 0
            else  // 其余时间
                i2c_scl <=  1'b1;  // 回到高，让 SDA 的 0→1 发生在高电平里 → STOP
        default:    i2c_scl <=  1'b1;  // 异常状态放开 SCL，别把总线拽死
    endcase

// i2c_sda_reg:sda数据缓存
always@(*)  // 组合逻辑：按状态决定此刻往 SDA 送什么位
    case    (state)  //--- SDA 的"发什么"表 ---
        IDLE:  // 空闲
            begin  //
                i2c_sda_reg <=  1'b1;  // SDA 释放为高，总线空闲
                rd_data_reg <=  8'd0;  // 顺手清掉上次读的移位缓存，避免读到旧值
            end  //
        START_1:  // 起始
            if(cnt_i2c_clk <= 2'd0)  // 第 1 拍
                i2c_sda_reg <=  1'b1;  // SDA 维持高
            else  // 从第 2 拍起
                i2c_sda_reg <=  1'b0;  // 在 SCL 还高的时候拉低 → START 条件
        SEND_D_ADDR:  // 发器件地址
            if(cnt_bit <= 3'd6)  // 前 7 位是地址
                i2c_sda_reg <=  device_addr_i[6 - cnt_bit];  // 高位先出：bit6 → bit0（用截出来的 7 位地址）
            else  // 第 8 位
                i2c_sda_reg <=  1'b0;  // 固定发 0 = 写方向
        ACK_1:  // 应答时隙
            i2c_sda_reg <=  1'b1;  // 主机放开 SDA，让从机拉低表示 ACK
        SEND_B_ADDR_H:  // 发地址高字节
            i2c_sda_reg <=  byte_addr[15 - cnt_bit];  // 高字节高位先出（bit15 → bit8）
        ACK_2:  // 应答时隙
            i2c_sda_reg <=  1'b1;  // 释放，收从机 ACK
        SEND_B_ADDR_L:  // 发地址低字节
            i2c_sda_reg <=  byte_addr[7 - cnt_bit];  // 低字节高位先出（bit7 → bit0）
        ACK_3:  // 应答时隙
            i2c_sda_reg <=  1'b1;  // 释放，收从机 ACK
        WR_DATA:  // 发数据
            i2c_sda_reg <=  wr_data[7 - cnt_bit];  // 要写的数据高位先出
        ACK_4:  // 应答时隙
            i2c_sda_reg <=  1'b1;  // 释放，收从机 ACK
        START_2:  // 重复起始
            if(cnt_i2c_clk <= 2'd1)  // 前 2 拍
                i2c_sda_reg <=  1'b1;  // 先把 SDA 放开回高
            else  // 后 2 拍
                i2c_sda_reg <=  1'b0;  // 再在 SCL 高电平里拉低 → Sr，把方向切成读
        SEND_RD_ADDR:  // 重发器件地址
            if(cnt_bit <= 3'd6)  // 前 7 位地址
                i2c_sda_reg <=  device_addr_i[6 - cnt_bit];  // 一样高位先出
            else  // 第 8 位
                i2c_sda_reg <=  1'b1;  // 这次发 1 = 读方向
        ACK_5:  // 应答时隙
            i2c_sda_reg <=  1'b1;  // 释放，收从机 ACK
        RD_DATA:  // 读数据
            if(cnt_i2c_clk  == 2'd2)  // 在 SCL 高电平正中间采（数据最稳）
                rd_data_reg[7 - cnt_bit]    <=  sda_in;  // 一位一位填进移位缓存，bit7 先来
            else  // 其余时间
                rd_data_reg <=  rd_data_reg;  // 保持
        N_ACK:  // 主机非应答
            i2c_sda_reg <=  1'b1;  // SDA 保持高 = NACK，告诉从机"到此为止"
        STOP:  // 停止条件
            if((cnt_bit == 3'd0) && (cnt_i2c_clk < 2'd3))  // 第 1 个位的前 3 拍
                i2c_sda_reg <=  1'b0;  // SDA 先在低处待着
            else  // 之后
                i2c_sda_reg <=  1'b1;  // SCL 还高时 SDA 0→1 → STOP
        default:  // 异常状态
            begin  //
                i2c_sda_reg <=  1'b1;  // 不驱动低电平，避免锁总线
                rd_data_reg <=  rd_data_reg;  // 移位缓存保持
            end  //
    endcase

// --- 输出整理：把内部状态翻译成上层友好的 i2c_end / rd_data ---
// rd_data:自i2c设备读出数据
always@(posedge i2c_clk or negedge sys_rst_n)  // i2c_clk 域，输出对齐时钟沿
    if(sys_rst_n == 1'b0)  // 复位
        rd_data <=  8'd0;  // 输出清 0
    else    if((state == RD_DATA) && (cnt_bit == 3'd7) && (cnt_i2c_clk == 2'd3))  // 读状态第 8 位的最后一拍
        rd_data <=  rd_data_reg;  // 8 位全齐了，整字节搬出来

// i2c_end:一次读/写结束信号
always@(posedge i2c_clk or negedge sys_rst_n)  // i2c_clk 域
    if(sys_rst_n == 1'b0)  // 复位
        i2c_end <=  1'b0;  // 结束标志清 0
    else    if((state == STOP) && (cnt_bit == 3'd3) &&(cnt_i2c_clk == 3))  // STOP 走完 4 个位的最后一拍
        i2c_end <=  1'b1;  // 打一个 i2c_clk（约 1µs）宽的脉冲，上层用它推进下一条
    else  // 其他时候
        i2c_end <=  1'b0;  // 只维持一拍

// --- 三态口处理：决定此刻谁在驱动 SDA，以及该送什么位 ---
// sda_in:sda输入数据寄存 —— 引脚上的真实电平
assign  sda_in = i2c_sda;  // 直接把双向引脚读回来
// sda_en:sda数据写入使能信号 —— 决定此刻谁在说
assign  sda_en = ((state == RD_DATA) || (state == ACK_1) || (state == ACK_2)  // 读数据和 5 个应答时隙里
                    || (state == ACK_3) || (state == ACK_4) || (state == ACK_5))  // 必须由从机驱动 SDA
                    ? 1'b0 : 1'b1;  // 这些状态释放总线(0=高阻)；其他状态主机驱动(1=输出)
// i2c_sda:输出至i2c设备的串行数据信号sda
assign  i2c_sda = (sda_en == 1'b1) ? i2c_sda_reg : 1'bz;  // 三态：该驱动就送 i2c_sda_reg，该释放就输出高阻（靠板上拉电阻拉高）

endmodule  // 模块结束
