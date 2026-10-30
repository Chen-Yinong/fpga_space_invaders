// ============================================================================
// 文件：board_cam/ov7725_cfg.v（模块名 ov7725_cfg）—— 逐行注释版（原文件 151 行）
// 作用：一张"寄存器配置表 + 顺序播放器"。上电后按顺序把 71 条 {寄存器地址, 寄存器值} 通过
//       I2C 写进 OV7725，把摄像头从默认状态配成 640×480、RGB565、自动曝光/白平衡全关的固定参数状态。
// 怎么通信：本模块自己不发 I2C 波形，它只负责"给地址和数据 + 收完成信号"：
//       cfg_data（{reg_addr, reg_val}）→ i2c_ctrl 发出去 → 传完回来 cfg_end → 换下一条。
// 状态机：严格说没有 state 变量，是一个"计数器驱动的顺序机"：
//       上电等 1023 拍 → 发第 0 条 → 等 cfg_end → 发第 1 条 → …… → 第 70 条发完 → cfg_done=1。
// 关键时序/魔数：
//       REG_NUM       = 71    → 配置表一共 71 条（数组下标 0~70）
//       CNT_WAIT_MAX  = 1023  → 上电等待计数上限。本模块时钟 = i2c_clk = 1MHz，
//                               所以 1023 拍 ≈ 1.02ms，就是给 OV7725 上电稳定留的延时。
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

module  ov7725_cfg  // 模块声明：OV7725 寄存器配置表播放器（无端口参数）
(  // 端口列表开始
    input   wire            sys_clk     ,   //系统时钟,由iic模块传入 —— 实际接的是 i2c_ctrl 的 i2c_clk（1MHz），不是板上 50MHz 晶振
    input   wire            sys_rst_n   ,   //系统复位,低有效 —— 异步复位
    input   wire            cfg_end     ,   //单个寄存器配置完成 —— i2c_ctrl 传完一条时给的 1 拍脉冲

    output  reg             cfg_start   ,   //单个寄存器配置触发信号 —— 拉高 1 拍，让 i2c_ctrl 开始发下一条
    output  wire    [15:0]  cfg_data    ,   //ID,REG_ADDR,REG_VAL —— 高 8 位是寄存器地址、低 8 位是要写的值（OV7725 用 8 位地址，所以这 16 位刚好）
    output  reg             cfg_done        //寄存器配置完成 —— 71 条全部写完就拉高并一直保持，上层用它判断"摄像头可以出图了"
);  // 端口列表结束

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//

//parameter define
parameter   REG_NUM         =   7'd71   ;   //总共需要配置的寄存器个数 —— 71，配置表数组就是 0~70；改表长必须同步改这个数
parameter   CNT_WAIT_MAX    =   10'd1023;   //寄存器配置等待计数最大值 —— 1023 拍 × 1µs = 约 1.02ms，上电后先等这么久再碰 SCCB

//wire  define
wire    [15:0]  cfg_data_reg[REG_NUM-1:0]   ;   //寄存器配置数据暂存 —— 71×16bit 的查找表（综合成一块 ROM，靠 reg_num 当读地址）

//reg   define
reg     [9:0]   cnt_wait    ;   //寄存器配置等待计数器 —— 10 位宽，刚好能数到 1023，数满就停住不再动
reg     [6:0]   reg_num     ;   //配置寄存器个数 —— 同时是配置表的读地址（0~71，7 位宽够用）

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
//cnt_wait:寄存器配置等待计数器
always@(posedge sys_clk or negedge sys_rst_n)  // 1MHz 时钟域，上升沿触发
    if(sys_rst_n == 1'b0)  // 复位
        cnt_wait    <=  15'd0;  // 清零（这里写 15'd0 而寄存器只有 10 位，高位被截掉，等效于 0，不影响功能）
    else    if(cnt_wait < CNT_WAIT_MAX)  // 还没数到上限
        cnt_wait    <=  cnt_wait + 1'b1;  // 一直往上数
// --- 数到 1023 后不再有 else，计数器保持 1023 不动：所以"上电等待"只会发生一次，之后不会再插延时 ---

//reg_num:配置寄存器个数
always@(posedge sys_clk or negedge sys_rst_n)  // 1MHz 时钟域
    if(sys_rst_n == 1'b0)  // 复位
        reg_num <=  7'd0;  // 从配置表第 0 条开始
    else    if(cfg_end == 1'b1)  // 每收到一次"这条传完了"
        reg_num <=  reg_num + 1'b1;  // 读地址 +1，自动指向下一条；数到 71 后自然停在 71（表已读完）

//cfg_start:单个寄存器配置触发信号
always@(posedge sys_clk or negedge sys_rst_n)  // 1MHz 时钟域
    if(sys_rst_n == 1'b0)  // 复位
        cfg_start   <=  1'b0;  // 不启动
    else    if(cnt_wait == (CNT_WAIT_MAX - 1'b1))  // 上电延时数到 1022（下一拍就满 1023）
        cfg_start   <=  1'b1;  // 打出第 1 个启动脉冲，开始配第 0 条
    else    if((cfg_end == 1'b1) && (reg_num < REG_NUM))  // 上一条传完，且还没到表尾
        cfg_start   <=  1'b1;  // 立刻触发下一条（一条接一条地灌）
    else  // 其他情况
        cfg_start   <=  1'b0;  // 平时保持低，只在需要时给 1 拍

//cfg_done:寄存器配置完成
always@(posedge sys_clk or negedge sys_rst_n)  // 1MHz 时钟域
    if(sys_rst_n == 1'b0)  // 复位
        cfg_done    <=  1'b0;  // 未完成
    else    if((reg_num == REG_NUM) && (cfg_end == 1'b1))  // 第 71 条（reg_num 已数到 71）也传完了
        cfg_done    <=  1'b1;  // 置位并保持：配置阶段结束，摄像头开始出稳定图像
// --- 注意 cfg_done 只置不清：一旦配完就一直为 1，中途复位才会清掉 ---

//cfg_data:ID,REG_ADDR,REG_VAL
assign  cfg_data = (cfg_done == 1'b1) ? 16'h0000 : cfg_data_reg[reg_num];  // 还没配完就把当前条送出去；配完后强制送 0（避免 reg_num=71 越界读表，也让总线数据稳定为 0）

//----------------------------------------------------
//cfg_data_reg：寄存器配置数据暂存  ID   REG_ADDR REG_VAL
// --- 第 1 组：输出时序与图像窗口（决定"多少像素 × 多少行、从传感器的哪一块取"）---
assign  cfg_data_reg[00]  =       {8'h3d,  8'h03};  // 0x3D=COM12 输出时序控制：0x03 让 PCLK/HREF/VSYNC 的相位对齐到 FPGA 能采的样子（官方 RGB565 配置的固定值）
assign  cfg_data_reg[01]  =       {8'h15,  8'h02};  // 0x15=COM10 输出时序控制：0x02 置 bit1，决定 PCLK 极性（FPGA 在 pclk 上升沿采到的是稳定数据）

assign  cfg_data_reg[02]  =       {8'h17,  8'h23};//640*480 : 23 a0 07 f0 —— 0x17=HSTART 高 8 位（HREF 起点[9:2]）：0x23×4 = 140，有效图像从第 140 列开始
assign  cfg_data_reg[03]  =       {8'h18,  8'ha0};//320*240 : 3f 50 03 78 —— 0x18=HSIZE 高 8 位（HREF 宽度[9:2]）：0xA0×4 = 640 → 每行 640 像素（VGA 宽）；切 320×240 就改 0x3F/0x50 那组
assign  cfg_data_reg[04]  =       {8'h19,  8'h07};  // 0x19=VSTART 高 8 位：0x07×4 = 28 → 有效图像从第 28 行开始（上面留黑行）
assign  cfg_data_reg[05]  =       {8'h1a,  8'hf0};  // 0x1A=VSIZE 高 8 位：0xF0×4 = 960 个单位，OV7725 竖直方向 2 行算 1 个单位 → 480 行（VGA 高）

assign  cfg_data_reg[06]  =       {8'h32,  8'h00};  // 0x32=HREF 控制：0x00 = HREF 不翻转、不加延迟，高电平期间就是有效像素
assign  cfg_data_reg[07]  =       {8'h29,  8'hA0};//640*480 : A0   320*240 : 50 —— 0x29 是 HSTART 的低位补齐寄存器（只用到最低 2 位）：0xA0 实际取低 2 位=0，表示没有额外低位偏移
assign  cfg_data_reg[08]  =       {8'h2a,  8'h00};  // 0x2A=HSIZE 低位补齐：0（640、320 都是 4 的倍数，低位永远是 0）
assign  cfg_data_reg[09]  =       {8'h2b,  8'h00};  // 0x2B=VSTART 低位补齐：0（起点 28 行是 4 的倍数）
assign  cfg_data_reg[10]  =       {8'h2c,  8'hF0};//640*480 : F0   320*240 : 78 —— 0x2C=VSIZE 低位补齐：同样只取低 2 位=0
assign  cfg_data_reg[11]  =       {8'h0d,  8'h41};  // 0x0D=COM4：bit[7:6]=01 选 PLL 倍频档 + 低位带 AEC 的 LSB，这条给传感器内部时钟提速
assign  cfg_data_reg[12]  =       {8'h11,  8'h00};  // 0x11=CLKRC 内部时钟分频：0x00 = 不分频，PCLK 由 XCLK 经 PLL 直接得到，像素时钟最快
assign  cfg_data_reg[13]  =       {8'h12,  8'h06};  // 0x12=COM7 输出格式总开关：0x06 置 bit2/bit1 → 选 RGB 输出（RGB565），不用再做 YUV 转换
assign  cfg_data_reg[14]  =       {8'h0c,  8'hd0};  // 0x0C=COM3：0xD0=1101_0000，置 bit7/6/4，RGB565 + 内部时钟直通时的官方搭配（数据位对齐、UV 通路使能）
// --- 第 2 组：图像质量（DSP）与自动调节开关 ---
assign  cfg_data_reg[15]  =       {8'h42,  8'h7f};  // 0x42 DSP 控制：0x7F=0111_1111，几乎把所有自动调节使能位都打开（白平衡/亮度相关）
assign  cfg_data_reg[16]  =       {8'h4d,  8'h09};  // 0x4D DSP 参数：0x09 是官方推荐值，微调 AWB 与色彩矩阵
assign  cfg_data_reg[17]  =       {8'h63,  8'hf0};  // 0x63 镜头/暗角补偿：0xF0 高 4 位全 1，压住画面四角的偏色
assign  cfg_data_reg[18]  =       {8'h64,  8'hff};  // 0x64 镜头补偿：0xFF 全 1 = 补偿量拉满
assign  cfg_data_reg[19]  =       {8'h65,  8'h00};  // 0x65 镜头补偿：0x00 关闭这一项的偏移，避免画面整体偏色
assign  cfg_data_reg[20]  =       {8'h66,  8'h00};  // 0x66 镜头补偿：0x00
assign  cfg_data_reg[21]  =       {8'h67,  8'h00};  // 0x67 镜头补偿：0x00
assign  cfg_data_reg[22]  =       {8'h13,  8'hf8};//COM8: 关 AEC/AWB/AGC（bit2/1/0=0）—— 0x13=COM8，bit2=AGC、bit1=AWB、bit0=AEC 使能位全 0：亮度/颜色/曝光都改手动
assign  cfg_data_reg[23]  =       {8'h0f,  8'hc5};  // 0x0F=COM9 AGC 增益上限：0xC5 的 bit[6:4]=100 → 最大 32 倍增益
assign  cfg_data_reg[24]  =       {8'h14,  8'h11};  // 0x14=COM13：0x11 置 bit4+bit0，打开 UV 自动调整和 gamma 补偿
assign  cfg_data_reg[25]  =       {8'h22,  8'h98};  // 0x22 手动白平衡增益（B 蓝）：AWB 关了靠这组固定增益定色温，0x98 适合室内暖光
assign  cfg_data_reg[26]  =       {8'h23,  8'h03};  // 0x23 手动白平衡增益（R 红）：0x03
assign  cfg_data_reg[27]  =       {8'h24,  8'h40};  // 0x24 手动白平衡增益（Gb 绿蓝）：0x40
assign  cfg_data_reg[28]  =       {8'h25,  8'h30};  // 0x25 手动白平衡增益（Gr 绿红）：0x30
assign  cfg_data_reg[29]  =       {8'h26,  8'ha1};  // 0x26 白平衡补充控制：0xA1 让上面 4 个手动增益真正生效
assign  cfg_data_reg[30]  =       {8'h6b,  8'haa};  // 0x6B=DBLV PLL 控制：0xAA=1010_1010，bit[7:6]=10 选倍频档，配合 0x11=0x00 决定最终 PCLK
assign  cfg_data_reg[31]  =       {8'h13,  8'hf8};//COM8: 关 AEC/AWB/AGC —— 再写一次保险：后面还要下 DSP 参数，防止中途把自动调节又带开
assign  cfg_data_reg[32]  =       {8'h90,  8'h0a};  // 0x90 开始是"自动锐度/降噪/边缘增强"组（0x90~0x9C）：决定画面锐不锐、噪点多不多，0x0A 是起始强度
assign  cfg_data_reg[33]  =       {8'h91,  8'h01};  // 0x91 同一组，锐度参数 0x01
assign  cfg_data_reg[34]  =       {8'h92,  8'h01};  // 0x92 同一组，0x01
assign  cfg_data_reg[35]  =       {8'h93,  8'h01};  // 0x93 同一组，0x01
assign  cfg_data_reg[36]  =       {8'h94,  8'h5f};  // 0x94 同一组，0x5F 是阈值项
assign  cfg_data_reg[37]  =       {8'h95,  8'h53};  // 0x95 同一组，0x53
assign  cfg_data_reg[38]  =       {8'h96,  8'h11};  // 0x96 同一组，0x11
assign  cfg_data_reg[39]  =       {8'h97,  8'h1a};  // 0x97 同一组，0x1A
assign  cfg_data_reg[40]  =       {8'h98,  8'h3d};  // 0x98 同一组，0x3D
assign  cfg_data_reg[41]  =       {8'h99,  8'h5a};  // 0x99 同一组，0x5A
assign  cfg_data_reg[42]  =       {8'h9a,  8'h1e};  // 0x9A 同一组，0x1E
assign  cfg_data_reg[43]  =       {8'h9b,  8'h3f};  // 0x9B 同一组，0x3F
assign  cfg_data_reg[44]  =       {8'h9c,  8'h25};  // 0x9C 同一组，0x25
assign  cfg_data_reg[45]  =       {8'h9e,  8'h81};  // 0x9E 这一组的末项：0x81=1000_0001，最高位是总使能
assign  cfg_data_reg[46]  =       {8'ha6,  8'h06};  // 0xA6=SDE 特殊数字特效（黑白/负片/偏色）：0x06 = 普通彩色，特效全关
assign  cfg_data_reg[47]  =       {8'ha7,  8'h65};  // 0xA7 边缘/去噪参数：0x65
assign  cfg_data_reg[48]  =       {8'ha8,  8'h65};  // 0xA8 边缘/去噪参数：0x65
assign  cfg_data_reg[49]  =       {8'ha9,  8'h80};  // 0xA9：0x80=1000_0000，最高位使能这一项
assign  cfg_data_reg[50]  =       {8'haa,  8'h80};  // 0xAA：0x80 同上
// --- 第 3 组：gamma 曲线（0x7E~0x8C 共 15 个拐点，数值从 0x0C 单调升到 0xE8）---
assign  cfg_data_reg[51]  =       {8'h7e,  8'h0c};  // 0x7E gamma 第 1 点（最暗处）：0x0C 越小暗部越黑
assign  cfg_data_reg[52]  =       {8'h7f,  8'h16};  // 0x7F gamma 第 2 点：0x16
assign  cfg_data_reg[53]  =       {8'h80,  8'h2a};  // 0x80 gamma 第 3 点：0x2A
assign  cfg_data_reg[54]  =       {8'h81,  8'h4e};  // 0x81 gamma 第 4 点：0x4E
assign  cfg_data_reg[55]  =       {8'h82,  8'h61};  // 0x82 gamma 第 5 点：0x61
assign  cfg_data_reg[56]  =       {8'h83,  8'h6f};  // 0x83 gamma 第 6 点：0x6F
assign  cfg_data_reg[57]  =       {8'h84,  8'h7b};  // 0x84 gamma 第 7 点：0x7B
assign  cfg_data_reg[58]  =       {8'h85,  8'h86};  // 0x85 gamma 第 8 点（中间调）：0x86
assign  cfg_data_reg[59]  =       {8'h86,  8'h8e};  // 0x86 gamma 第 9 点：0x8E
assign  cfg_data_reg[60]  =       {8'h87,  8'h97};  // 0x87 gamma 第 10 点：0x97
assign  cfg_data_reg[61]  =       {8'h88,  8'ha4};  // 0x88 gamma 第 11 点：0xA4
assign  cfg_data_reg[62]  =       {8'h89,  8'haf};  // 0x89 gamma 第 12 点：0xAF
assign  cfg_data_reg[63]  =       {8'h8a,  8'hc5};  // 0x8A gamma 第 13 点：0xC5
assign  cfg_data_reg[64]  =       {8'h8b,  8'hd7};  // 0x8B gamma 第 14 点：0xD7
assign  cfg_data_reg[65]  =       {8'h8c,  8'he8};  // 0x8C gamma 第 15 点（最亮处）：0xE8；整条曲线压暗部、拉中间调，画面更通透
assign  cfg_data_reg[66]  =       {8'h8d,  8'h20};  // 0x8D gamma 曲线收尾/复位值：0x20=0010_0000
// --- 第 4 组：最后两条补丁（先关自动、再手动锁曝光）---
assign  cfg_data_reg[67]  =       {8'h0e,  8'h65};  // 0x0E=COM5：0x65 打开夜间模式自动切换等亮度相关开关
assign  cfg_data_reg[68]  =       {8'h09,  8'h00};  // 0x09=COM2：0x00 设置输出驱动能力/数据位宽相关位（8 位并口输出）
assign  cfg_data_reg[69]  =       {8'h08,  8'h02};//AECH: 固定曝光高字节 AEC[15:8] —— 手动曝光值的高 8 位 = 0x02
assign  cfg_data_reg[70]  =       {8'h10,  8'h00};//AEC:  固定曝光低字节 AEC[7:0] —— 曝光值 = 0x0200 = 512 行时间；因为 0x13 已关 AEC，这就是一个恒定曝光，画面亮度不随环境抖
//-------------------------------------------------------

endmodule  // 模块结束
