// ============================================================================
// 文件：board_hdmi/hdmi_i2c.v（模块名 hdmi_i2c）—— 逐行注释版（原文件 68 行）
// 作用：HDMI 配置子系统顶层，纯"连线 + 参数"，把两个子模块拼起来：
//       i2c_ctrl（通用 I2C 主机） + hdmi_cfg（6 条寄存器表）
// 怎么通信：用 I2C 两根线（sccb_scl/sccb_sda）把 HDMI 发送芯片（板上 SiI9134）的内部寄存器配好，
//       配完之后芯片才开始按 FPGA 送来的像素输出 TMDS 信号。
// 和摄像头那套（board_cam/ov7725_top.v）的区别：
//       1) 这里的 i2c_ctrl 是"通用版"，器件地址是端口 device_addr，每条命令自带地址（cfg_data[31:24]）；
//       2) 寄存器地址是 16 位（cfg_data[23:8]），摄像头那边只有 8 位；
//       3) 配置表只有 6 条，摄像头有 71 条。
// 关键时序：CLK_FREQ=25MHz、SCL_FREQ=250kHz
//       → CNT_CLK_MAX = (25M/250k)>>3 = 100>>3 = 12
//       → i2c_clk = 25MHz/(2×12) ≈ 1.042MHz → SCL = i2c_clk/4 ≈ 260kHz（贴近 250kHz）
//       → hdmi_cfg 用这个 i2c_clk 当时钟，它的 CNT_WAIT_MAX=1023 约等于 0.98ms 上电延时。
// 注意：端口注释写的是"系统时钟"，但 CLK_FREQ 填的是 25MHz，两者必须一致，否则 SCL 会按比例跑偏。
// 注释格式约定：原文已有的行尾注释保留并就地续写（用 —— 连接）；原来没有注释的行在行尾追加 "  // ..."。
// ============================================================================
`timescale 1ns / 1ps  // 仿真时间单位 1ns、精度 1ps（注意这份文件写的是 1ps，比其他几个文件精细一档，只影响仿真）
////////////////////////////////////////////////////////////////////////  // 分隔线：原始作者声明块开始，保留原样
// Author        : EmbedFire  // 原作者：野火（EmbedFire）FPGA 教程团队
// 实验平台: 野火FPGA系列开发板  // 代码来自野火开发板例程
// 公司    : http://www.embedfire.com  // 厂商网址
// 论坛    : http://www.firebbs.cn  // 技术论坛
// 淘宝    : https://fire-stm32.taobao.com  // 淘宝店铺
////////////////////////////////////////////////////////////////////////  // 分隔线：作者声明块结束


module hdmi_i2c(  // 模块声明：HDMI 配置子系统顶层
    input   wire            sys_clk         ,   //系统时钟 —— 板上主时钟，本文件按 25MHz 配给 I2C 模块
    input   wire            sys_rst_n       ,   //复位信号 —— 低有效，全局异步复位

    output  wire            cfg_done        ,   //寄存器配置完成 —— 6 条都写完了，上层用它启动 HDMI 数据通路
    output  wire            sccb_scl        ,   //SCL —— HDMI 芯片的 I2C 时钟，直接出引脚
    inout   wire            sccb_sda           //SDA —— 双向数据线，板上要有上拉电阻


    );  // 端口列表结束（这里多空了两行，只是排版习惯）
    
    
//parameter define
parameter    BIT_CTRL   =  1'b0         ; // 字地址位控制参数(16b/8b) —— 0 = 只发地址低字节（跳过 SEND_B_ADDR_H 分支）；这里够用是因为 6 条命令的寄存器地址高字节全是 0x00
parameter    CLK_FREQ   = 26'd25_000_000; // i2c_dri模块的驱动时钟频率(CLK_FREQ) —— 必须等于实际 sys_clk；25MHz 算出来 SCL≈260kHz
parameter    I2C_FREQ   = 18'd250_000   ; // I2C的SCL时钟频率 —— 目标 250kHz，远低于 I2C 快速模式 400kHz 上限

//wire  define
wire            cfg_end     ;  // i2c_ctrl 传完一条后给的 1 拍脉冲，作为配置表的推进节拍
wire            cfg_start   ;  // hdmi_cfg 给 i2c_ctrl 的启动脉冲
wire    [31:0]  cfg_data    ;  // 32 位配置命令：{器件地址, 寄存器地址 16 位, 数据}
wire            cfg_clk     ;  // i2c_ctrl 输出的 i2c_clk（约 1MHz），在这里当作 hdmi_cfg 的时钟
// --- 子模块 1：通用 I2C 主机，只管发/收字节，不关心内容 ---
i2c_ctrl  // 实例化通用 I2C 主机（board_hdmi 目录下这个文件里模块名就叫 i2c_ctrl）
#(  // 参数覆盖开始
    .SYS_CLK_FREQ   (CLK_FREQ   ), //i2c_ctrl模块系统时钟频率 —— 25MHz，用来算 cnt_clk 分频比
    .SCL_FREQ       (I2C_FREQ   )  //i2c的SCL时钟频率 —— 250kHz
)  //
i2c_ctrl_inst  // 实例名
(  // 端口连接开始
    .sys_clk     (sys_clk       ),   //输入系统时钟,50MHz —— 接板上主时钟（注释写 50MHz，但本文件参数按 25MHz 算，两者应一致）
    .sys_rst_n   (sys_rst_n     ),   //输入复位信号,低电平有效 —— 直接接全局复位
    .wr_en       (1'b1          ),   //输入写使能信号 —— 恒 1：只写不读，所以状态机 ACK_3 后固定走 WR_DATA
    .rd_en       (              ),   //输入读使能信号 —— 悬空：从不发读命令
    .i2c_start   (cfg_start     ),   //输入i2c触发信号 —— 由 hdmi_cfg 发起
    .addr_num    (BIT_CTRL      ),   //输入i2c字节地址字节数 —— 0：只发地址低字节（走 SEND_B_ADDR_L，跳过高字节）
    .device_addr (cfg_data[31:24]),  // 器件地址 —— 每条命令自带：0x72 / 0x7A / 0x60 三段寄存器空间靠这个区分
    .byte_addr   (cfg_data[23:8]),   //输入i2c字节地址 —— 取中间 16 位当寄存器地址（高字节相当于页号）
    .wr_data     (cfg_data[7:0] ),   //输入i2c设备数据 —— 取低 8 位当要写的值

    .rd_data     (              ),   //输出i2c设备读取数据 —— 不用，悬空
    .i2c_end     (cfg_end       ),   //i2c一次读/写操作完成 —— 变成配置表的推进节拍
    .i2c_clk     (cfg_clk       ),   //i2c驱动时钟 —— 约 1MHz，反过来给 hdmi_cfg 当系统时钟
    .i2c_scl     (sccb_scl      ),   //输出至i2c设备的串行时钟信号scl —— 直接出引脚
    .i2c_sda     (sccb_sda      )    //输出至i2c设备的串行数据信号sda —— 双向直连
);  //

// --- 子模块 2：6 条寄存器初始化表，用 cfg_end 当节拍往前推 ---
//------------- hdmi_cfg_inst -------------
hdmi_cfg  hdmi_cfg_inst(  // 实例化 HDMI 寄存器配置表模块

    .sys_clk        (cfg_clk    ),   //系统时钟,由iic模块传入 —— 接 i2c_clk（约 1MHz），所以表里的 CNT_WAIT_MAX=1023 ≈ 1ms 上电延时
    .sys_rst_n      (sys_rst_n  ),   //系统复位,低有效 —— 直接接全局复位
    .cfg_end        (cfg_end    ),   //单个寄存器配置完成 —— 收到就换下一条

    .cfg_start      (cfg_start  ),   //单个寄存器配置触发信号 —— 送回 i2c_ctrl 发起传输
    .cfg_data       (cfg_data   ),   //ID,REG_ADDR,REG_VAL —— 32 位整条送出（含器件地址）
    .cfg_done       (cfg_done   )    //寄存器配置完成 —— 直接作为模块输出
);  //
endmodule  // 模块结束
