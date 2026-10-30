# 光流版「太空侵略者」工程 —— 逐行注释版索引

这份目录是队友的 `is-it-possible-to-ai-it-perfect/cam_game_optiflowverison` 工程**全部 25 个源文件的带注释副本**：
原文件每一行都**原样保留**（已在脚本里逐行校验：25 个文件、约 3000 行，缺失 = 0），
只是在行尾（或上方）加了中文说明。建议在 VS Code 里用「分屏对照」看：左边原文件、右边这里的注释版。

## 怎么用

1. VS Code 里 `Ctrl+Shift+P` → `File: Compare Active File With...`，选同名注释版文件，就能左右对照。
2. 想快速查某个信号是干什么的：在注释版里 `Ctrl+F` 搜信号名。
3. 注释里凡是写「★」的段落，是这个模块最值得看的知识点。

## 文件对照表

### 一、光流算法核心（重点，先看这几个）

| 注释版文件 | 原文件 | 行数 | 这个文件在干嘛 |
|---|---|---|---|
| `rgb2gray.sv` | `src/rtl/rgb2gray.sv` | 21 | RGB565 → 灰度。光流只关心亮度变化，转灰度既省存储也去掉颜色干扰 |
| `gray_framebuf.sv` | `src/rtl/gray_framebuf.sv` | 59 | 一整帧灰度的双缓冲（乒乓）。光流要同时拿到「上一帧」和「这一帧」才能算位移 |
| `flow_linebuf.sv` | `src/rtl/flow_linebuf.sv` | 29 | 延迟一行的行缓冲，让像素能同时看到「左邻」和「上邻」→ 才能算梯度 Ix、Iy |
| `lk_flow.sv` | `src/rtl/lk_flow.sv` | 333 | **灵魂**：Lucas-Kanade 光流。2×2 抽点 → 16×16 分块 → 累加 A~E → 解方程得 (u,v) |
| `div_pipe.sv` | `src/rtl/div_pipe.sv` | 84 | 定点除法器（恢复余数法，70 拍流水）。LK 最后要除两次，FPGA 没有现成除法器 |
| `flow_tag_ram.sv` | `src/rtl/flow_tag_ram.sv` | 25 | 300×2bit 的双口 RAM，存「每个块的结论（左/右/不动）」，给显示侧读 |
| `flow_fsm.sv` | `src/rtl/flow_fsm.sv` | 122 | 投票 + 漏桶积分。300 个块投票 → 每帧定一次方向 → 连续同向才点亮 LED，静止会自动漏电回中立 |

### 二、游戏本体（按键版和光流版共用）

| 注释版文件 | 原文件 | 行数 | 这个文件在干嘛 |
|---|---|---|---|
| `game_core.sv` | `src/rtl/game_core.sv` | 612 | 游戏大脑：55 只外星人（11×5 编队）、6 条命、6 个子弹槽、4 个掩体、UFO、三关、计分、胜负 |
| `sprite_render.sv` | `src/rtl/sprite_render.sv` | 257 | 画家：给一个像素坐标，立刻算出这个点该是什么颜色（纯组合逻辑，一拍都不能拖） |
| `vga_timing.sv` | `src/rtl/vga_timing.sv` | 43 | 坐标发生器：数 800×525 个拍子，输出 x、y、hsync、vsync、DE |
| `debounce.sv` | `src/rtl/debounce.sv` | 23 | 按键消抖：电平稳定 5ms 才认可 |

### 三、顶层（两个版本各一个）

| 注释版文件 | 原文件 | 行数 | 这个文件在干嘛 |
|---|---|---|---|
| `top_cam_game.sv` | `src/rtl/top_cam_game.sv` | 232 | 手势版顶层：OV7725 → 灰度 → 光流 → 左右命令 → 游戏 → HDMI |
| `top_button_game.sv` | `src/rtl/top_button_game.sv` | 138 | 按键版顶层：没有摄像头，四个按键直接控制 |

### 四、板级驱动（厂商例程改写，接口固定，不用深究但要知道在干嘛）

| 注释版文件 | 原文件 | 行数 | 这个文件在干嘛 |
|---|---|---|---|
| `board_cam/ov7725_top.v` | 同名 | 97 | 摄像头顶层：上电复位 → 发配置 → 收数据，打包成 `cam_pclk/cam_href/cam_vsync/cam_data` |
| `board_cam/ov7725_cfg.v` | 同名 | 151 | 通过 SCCB（类 I2C）往 OV7725 寄存器写配置表（分辨率、输出格式 RGB565 等） |
| `board_cam/ov7725_data.v` | 同名 | 120 | 把 DVP 的 8 位并行数据按 pclk 拼成 16 位（RGB565 一个像素要两个 pclk） |
| `board_cam/i2c_ctrl.v` | 同名 | 346 | 通用 I2C 主机（16 个状态），摄像头配置就靠它 |
| `board_hdmi/hdmi_cfg.v` | 同名 | 88 | HDMI 发送芯片（SiI9134 类）的配置表 |
| `board_hdmi/hdmi_i2c.v` | 同名 | 68 | 给 HDMI 芯片专用的 I2C 主机（简化版，见下面「两个坑」） |
| `board_hdmi/i2c_ctrl.v` | 同名 | 348 | 又一个通用 I2C 主机（和 board_cam 那份几乎一样，模块名不同） |

### 五、仿真 / 脚本 / 约束（想上板或跑仿真才需要看）

| 注释版文件 | 原文件 | 行数 | 这个文件在干嘛 |
|---|---|---|---|
| `testbench/tb_game_core.sv` | `sim/tb_game_core.sv` | 85 | 游戏本体自动体检：12 条断言，把 TICK_DIV 改成 10 让游戏「快进」 |
| `tcl/create_project_cam.tcl` | 同名 | 29 | 一键重建手势版工程（顶层 top_cam_game + 摄像头驱动 + 光流） |
| `tcl/create_project.tcl` | 同名 | 28 | 一键重建按键版工程（顶层 top_button_game，不加摄像头驱动） |
| `constraints/top_cam_game.xdc` | 同名 | 131 | 手势版引脚表：50MHz 晶振、摄像头 20 根线、按键、HDMI 24 位、3 个 LED、pclk 时钟与 CDC 例外 |
| `constraints/top_button_game.xdc` | 同名 | 87 | 按键版引脚表：比上面少了摄像头，多了 key0/key1（本工程未使用） |

## 读代码建议顺序

1. `vga_timing.sv` → 先搞清「像素是怎么被一个个点出来的」
2. `sprite_render.sv` → 再搞清「一个坐标怎么变成颜色」
3. `game_core.sv` → 然后看游戏规则（这个最长，可分段看：状态机 → 输入 → 子弹 → 敌人 → 碰撞 → 计分）
4. `rgb2gray` → `gray_framebuf` → `flow_linebuf` → `lk_flow` → `div_pipe` → `flow_tag_ram` → `flow_fsm` → 光流这条链
5. 最后 `top_cam_game.sv` 把它们串起来

## 注释过程中发现的 3 个「注释与实现不符」的地方

这几个不是我们改出来的，是原工程本来就这样，写在这里免得你读代码时被绕进去：

1. **`board_cam/ov7725_data.v` 的 `PIC_WAIT`**：注释说是「等 10 个 pclk」，实际代码里每个 pclk 就加一，且复位后**第一个 vsync 就放行**，并没有真的等 10 个像素时钟。
2. **`board_hdmi/hdmi_i2c.v` 的 `BIT_CTRL`**：参数写成 0，导致 16 位寄存器地址的**高字节根本没发出去**。之所以没出错，是因为这张配置表里地址高字节全是 `0x00`。
3. **`board_hdmi/hdmi_i2c.v` 源文件是 GBK 编码**（不是 UTF-8），VS Code 打开可能是乱码，右下角切成 GBK 就好；注释版已统一转成 UTF-8。

另外 `game_core.sv` 里那段 `get_bunk_x` 用 `case` 返回固定坐标（32/108/184/260），注释写着「解耦 1152 位掩体动态寻址，彻底根治 Timing Optimization 综合卡死」——意思是原来的写法会对一个 1152 位的位向量做**变量下标访问**，综合出巨型 MUX，实现阶段直接卡死。这是个很值得记的坑。
