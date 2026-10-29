# AI 协作日志（AI Collaboration Log）

> 比赛评分项「大模型协作与技能包」占 15 分。本文件**从第一天开始记录**，且必须包含
> **失败与纠错轨迹**，不能只写成功案例。禁止事后补写、禁止伪造。

**记录格式**

```
### YYYY-MM-DD | 角色 | 工具与模型
- 目标：
- 提问（原样粘贴）：
- 回答要点：
- 采纳 / 否决 / 纠错：
- 产出物：
```

---

### 2026-10-11 | A（平台与集成） | Codex（GPT-5 系列，桌面版）

**目标**：完成第零阶段四项交付物——手势定义、时钟与接口标准、软件环境安装、仓库规范。

**提问（原样粘贴）**

```
第零阶段-本周周日：
定义四种用到的手势，确认全过程用的时钟频率、什么接口等关键标准。
安装vs code、vivado仿真、python图像处理库等其他的所需软件，约定仓库使用规范。
```

**AI 执行过程（可核查）**

1. 扫描工作区：`D:\fpga`（含比赛指南 PDF、LaTeX 计划书）、`D:\fpga\fpga_space_invaders`（git 仓库，远端 `Chen-Yinong/fpga_space_invaders`）。
2. 读取 `fpga_space_invaders_plan.tex`，提取角色划分（A 平台/集成、B 视觉/HLS、C 游戏/显示/验证）、WP0–WP6 工作包、架构链路与风险清单。
3. 探测本机环境：
   - `git --version` -> 2.56.0.windows.2（`D:\fpga\Git\cmd\git.exe`）
   - `python --version` -> **无输出且退出码 1**；`py -0p` -> Python 3.13.5
   - `node --version` -> v24.19.0
   - `code --version` -> 命令不存在；注册表查询 -> 未安装
   - `D:\fpga\2026.1\Vivado\bin` -> Vivado/Vitis 2026.1 已安装但不在 PATH
4. 安装软件：`winget install Microsoft.VisualStudioCode --scope user`；`py -m pip install -r requirements.txt` 等价包；`py -m pip install cocotb`。
5. 产出文档 `docs/gesture_spec.md`、`docs/interface_spec.md`、`docs/environment_setup.md`、`docs/repo_conventions.md`、`docs/phase0_checklist.md`，以及 `scripts/check_env.ps1`、`requirements.txt`。

**采纳**

- 以「传统视觉特征 + 小型决策器」而非 CNN 作为手势方案（与计划书一致，7 Series 资源可承受）。
- 手势方案确定为：移动用**空间位置 + 迟滞**，射击用**开合度下降沿**，开始用**往复挥手计数**；三者特征正交，可同时操作。
- 独热命令编码 `cmd[3:0]` + 单比特 `cmd_valid` 跨时钟域，避免多比特跨域毛刺。
- 采用 `scripts/check_env.ps1` 作为环境唯一验收入口（可重复、可交接）。

**纠错轨迹（重要）**

| # | AI 的错误 / 缺陷 | 发现方式 | 修正 |
| --- | --- | --- | --- |
| 1 | 首版 `check_env.ps1` 写成 **UTF-8 without BOM** | 执行脚本报 `Unexpected token 'PASS'`、`Missing closing '}'`，中文全部乱码 | 改为 **UTF-8 with BOM**，并在 `environment_setup.md` 第 3 节把「.ps1 必须带 BOM」列为硬性注意事项 |
| 2 | 脚本用 `code --version` 取版本，返回空字符串 | 自检输出 `VS Code PASS  | ...`（版本列为空） | 改用 `(Get-Item Code.exe).VersionInfo.ProductVersion`，得到 1.141.0 |
| 3 | 脚本读取 `Vivado\data\version` 作版本号，文件不存在 | 输出 `[版本 (未知版本)]` | 该路径实际文件是二进制 `version.dat`，改为从安装目录名 `2026.1` 推导版本 |
| 4 | 最初假设 `python` 命令可用 | `python --version` 无输出、退出码 1 | 查明是 **Microsoft Store 占位程序**；项目统一改用 `py -3` 或虚拟环境 python，并在文档中列为「关键坑」 |
| 5 | `environment_setup.md` 第 2.6 节误写入一行无关的 `winget install --id Bleachbit.BleachBit` | 自查文档时发现 | 删除，替换为正确的 iverilog 安装方式（choco / 官方安装包） |

> 说明：第 1 条是最典型的一类问题——AI 生成的脚本在本机「看起来没问题」，但被执行环境
> 的编码假设打败。这类问题只有**真的跑一遍**才能发现，因此本项目规定：任何脚本交付前必须实际执行。

**产出物**

| 路径 | 内容 |
| --- | --- |
| `docs/gesture_spec.md` | 四种手势定义（唯一权威），v1.0 冻结 |
| `docs/interface_spec.md` | 时钟/复位/总线/分辨率/坐标/延迟预算/端口契约，v1.0 冻结 |
| `docs/environment_setup.md` | 工具清单、安装步骤、常见坑、自检流程 |
| `docs/repo_conventions.md` | 目录/命名/分支/提交/PR/数据/AI 记录规范 |
| `docs/phase0_checklist.md` | 第零阶段交付清单与遗留问题 |
| `scripts/check_env.ps1` | 环境自检脚本（UTF-8 with BOM） |
| `requirements.txt` | Python 依赖声明 |

**待验证（不得当作已结论）**

- 手势阈值（张开 480 / 握拳 300 / 面积 2000–120000）为**基于经验的首版默认值**，
  必须由 B 用真实采集数据标定后才能写进最终报告。
- 「挥手计数」作为开始手势在现场光照下是否稳定，需要实测；备选方案为「中区停留 2 s」。
- MMCM 能否生成 25.175 MHz 需在 A 的真实板卡上验证。

---


---

### 2026-10-11（续） | A（平台与集成） | Codex（GPT-5 系列，桌面版）

**目标**：关闭第零阶段遗留的「板卡/器件型号未冻结」问题。

**提问（原样粘贴）**

```
artix-7
```

**AI 执行过程（可核查）**

1. 检索 `D:\fpga` 与仓库，未发现团队已有的板卡线索（无 xc7*/basys/nexys/arty 相关工程文件）。
2. 将器件系列冻结为 **Artix-7**：首选 **XC7A100T-1CSG324C**（Nexys A7 / Arty A7-100T），备选 **XC7A35T**（Basys 3）。
3. 更新 `docs/interface_spec.md` 至 **v1.1**：补充「无 PS 架构调整」对照表——摄像头初始化改由 PL I2C 主机、日志改由 PL UART、去掉 DDR 全帧缓冲默认改为行缓冲 + 双缓冲。
4. 同步更新 `check_env.ps1`（目标器件 PASS）、`phase0_checklist.md`（R1 关闭）、`architecture.md`（RK1 降级为已缓解）、`README.md`（器件表述）。

**采纳**

- 选 Artix-7 后**架构随之收紧**：所有原本交给 PS 的辅助功能（SCCB 配置、UART 日志、性能统计）全部下沉到 PL，更贴合「展示 FPGA 核心价值」的评分导向。

**纠错 / 权衡**

- 风险点：XC7A35T（Basys 3）若作为实际板卡，BRAM 偏紧，640×480 视频流水线 + 双缓冲可能吃紧。
  应对：已在该表注明「若用 35T，第 2 周先做资源预评估」，并把视觉处理分辨率下调到 320×240 作为默认缓冲策略。
- 尚未敲定具体开发板型号（Nexys A7 / Arty A7-100T / Basys 3），这决定 XDC 引脚与是否有板载 VGA，
  已保留为第 1 周唯一待办，不影响器件系列开工。

**产出物**

| 路径 | 内容 |
| --- | --- |
| `docs/interface_spec.md` | 升 v1.1，冻结 Artix-7 器件与架构调整 |
| `scripts/check_env.ps1` | 目标器件改为 PASS |
| `docs/phase0_checklist.md` | R1 关闭 |
| `docs/architecture.md` | RK1 状态更新 |
| `README.md` | 器件表述更新为 Artix-7 |

---


---

### 2026-10-15 ~ 2026-10-17 | C（游戏本体）+ A（板级集成） | Codex（GPT-5 系列，桌面版）

**目标**：把游戏本体做完整并上真板；接入 OV7725 摄像头手势；解决"战机一直向右"。

**里程碑**

1. 游戏本体 v2 上板可玩：自动连射（多子弹）、敌机子弹、生命/无敌、波次、HUD。
2. 板卡确认：**野火「升腾 Pro」XC7A100T-FGG484-2**，50MHz，HDMI（SiI9134），**OV7725** 摄像头。
3. 摄像头链路打通：OV7725(0x21) → DVP 采集 → RGB565→YCbCr → 肤色 → 质心速度 → 左/右/停 → 游戏。
4. 按团队方案加入：**按键触发肤色标定**（key1）+ **摄像头小窗预览**（右上角，肤色标绿，黄框为采样区）。

**关键问题与纠错（保留）**

| # | 现象 | 根因 | 修复 |
| --- | --- | --- | --- |
| 1 | 不按键战机一直左移 | 板载按键**低有效**，代码按高有效 | 顶层改为 `~key[n]` |
| 2 | 自动连射却不发射 | 点射脉冲 1ms < tick 周期 1.67ms，脉冲落在两次 tick 之间 | 脉冲加宽到 3ms |
| 3 | 综合后时序崩（WNS −15.2ns） | 6 子弹 × 50 敌机碰撞组合逻辑 60 级 | 列/行坐标预寄存 + 碰撞结果流水 + 视频输出流水 → WNS +8.9ns |
| 4 | 摄像头全屏红（cfg_done=0） | 摄像头是 **OV7725(0x21)**，误用 OV5640(0x3C) 配置，I2C 无 ACK 卡死 | 换用 `ov7725_top/ov7725_cfg` |
| 5 | 战机一直向右 | `dxs=xsum−xsum_prev` 声明为无符号，左移的负数变成约 40 亿 | 改为 `logic signed [33:0]` 有符号比较 |
| 6 | 采样后大部分画面变绿 | 采样 ROI 240×240 太大、min/max 范围过宽 | ROI 缩到 120×120，阈值改为「中点 ±12」 |
| 7 | 布线失败 IO Clock Placer | `cam1_pclk` 到 BUFG 走非专用路径 | `CLOCK_DEDICATED_ROUTE FALSE` + 显式 `create_clock` |
| 8 | CDC 路径时序违例 | cam1_pclk ↔ sys_clk ↔ clk_25m 多处跨域 | 补 `set_false_path` CDC 约束 |
| 9 | 综合报 `i2c_ctrl` 参数不存在 | HDMI 与摄像头两个 `i2c_ctrl` 模块重名 | 摄像头版改名 `cam_i2c_ctrl` |

**产出物**

- `src/rtl/`：`game_core`(v2)、`debounce`、`vga_timing`、`sprite_render`(多子弹+HUD)、`top_button_game`、`top_hdmi_game`、`top_cam_game`、`top_cam_test`、`cam_preview`、`cam_frame_buf`、`skin_calib`、`rgb2ycrcb`、`vision_gesture`
- `src/rtl/board/`：HDMI I2C（`i2c_ctrl/hdmi_cfg/hdmi_i2c`）；`board/cam/`：OV7725/OV5640 配置与采集
- `constraints/top_cam_game.xdc`：摄像头 + HDMI + 按键 + CDC 约束
- `scripts/`：`create_project` / `build_bitstream` / `build_game` / `build_camtest` / `program_fpga` / `program_camtest`
- `sim/`：`tb_game_core`(11 项)、`tb_gesture_dir_fsm`、`tb_render`、`tb_dyn_render`、一键运行脚本
- `docs/game_tuning.md`：游戏本体参数确认表

**验证数据**

- 仿真：`tb_game_core` 11/11 PASS；`tb_gesture_dir_fsm` 7/7 PASS；渲染 9 帧正常。
- 时序：`top_cam_game` WNS **+8.705ns**（全约束满足）；`top_cam_test` WNS +25.887ns。
- 上板：游戏可玩、HDMI 出图、摄像头出图、肤色识别正常。

**待验证 / 风险**

- 标定后的手势方向与灵敏度仍需现场实测（`K_PIX=6`、`MIN_PIX=2000`）。
- 摄像头 pclk 走非专用 IO→BUFG 路径（已放宽约束，24MHz 可接受，但属时序隐患）。
- 尚未写 Flash（当前 JTAG 烧写，掉电丢失）。
- `docs/interface_spec.md` 仍写 VGA/100MHz，需更新为 HDMI/50MHz/OV7725。

---


---

### 2026-10-17（续） | C（游戏本体）+ A（板级集成） | Codex（GPT-5 系列，桌面版）

**目标**：落地团队方案——**先采样肤色、再开始游戏、旁边显示摄像头小窗**。

**需求确认（团队）**
- 开机时不允许有默认肤色数据；必须先用按键采样才能开始游戏（每个人肤色不同）；
- 采样用板载按键；摄像头画面在游戏画面旁边开小窗；
- 只需要 1 个开始/暂停按键。

**实现**
1. `skin_calib.sv`：上电阈值置空（不匹配任何像素），`key1` 触发采样，采样完成后写入阈值。
2. 采样参数迭代：ROI 240×240 → 120×120 → **160×160**；采样帧数 30 → **45（约 1.5s）**；阈值由 min/max±8 → **范围中点 ±12**。
3. **合理性检查**：采样中点必须落在 `Cb∈[60,150]`、`Cr∈[110,200]` 内，否则判为“不像肤色”，**拒绝本次采样**（框保持红色），避免把背景误标成皮肤。
4. **全屏标定预览**：按 `key1` 期间整屏显示摄像头（320×240 帧缓存 2× 放大）+ 大黄框；采完自动回到游戏画面。
5. 游戏态：右上角 160×120 小窗显示摄像头（肤色标绿），框颜色表示状态：**红=未标定 / 黄=采样中 / 绿=完成**。
6. 未完成采样时 `skin` 强制为 0，且 `key0` 开始按键被门控（不能开始）。

**本轮发现的问题**

| # | 现象 | 根因 | 处理 |
| --- | --- | --- | --- |
| 10 | 按住 key1 没反应 / 手一直是绿的 | 上电用了默认肤色阈值，采样没有可见反馈 | 上电阈值置空；框颜色（红/黄/绿）反馈 |
| 11 | 采样后“环境变绿、手不绿” | 采样框太小、手没盖满，采到的是背景 | 框放大到 160×160；采样 1.5s；加合理性检查 |
| 12 | 采样体验差 | 小窗里的框太小、难对准 | 改为**全屏标定预览 + 大框**，采完自动切回游戏 |

**验证**
- RTL 全量 `xvlog` 编译通过；Vivado 综合/实现/比特流成功；`top_cam_game` WNS **+8.7ns**（全约束满足）。
- 上板：摄像头出图、肤色识别、全屏标定流程均已烧写验证（标定阈值仍需现场微调）。

**待办**
- 若全屏标定仍难对准：下一步改为“自动选取画面中最像肤色的区域”。
- 写 Flash，实现上电自动运行。
- 更新 `docs/interface_spec.md`（VGA→HDMI、50MHz、OV7725）。

---

### 2026-10-17（续） | C（游戏本体）+ A（板级集成） | Codex（GPT-5 系列，桌面版）

**目标**：复核远端仓库目录重构，并把 Vivado 工程更新到当前源码版本。

**执行与结论**
- 已重新 fetch `origin/main`，当前远端仍为 `9359f76 do nothing`，没有比本地更新的提交。
- 新结构把 Vivado 工程与说明文档分开，顶层更清爽；但 `d32030c simplify the directory` 同时删除了 `src/rtl`、`sim`、`constraints`、`data` 与 `web-game`，新机器直接 clone 后无法构建。
- 已恢复构建必需目录到工程目录下，并把 `.xpr` 中写死的 `C:/Users/Lenovo/...` 路径全部改为 `$PPRDIR/...` 相对路径。
- `fpga_space_invaders.xpr` 当前包含 25 个 RTL 文件，综合顶层为 `top_cam_game`；新增 `sim_1` 文件集，加入 5 个 testbench，仿真顶层为 `tb_game_core`。
- `create_project.tcl` 同步补上 `sim_1`，以后重建工程不会漏掉仿真文件。
- 全量 `xvlog` 编译时发现 `top_cam_game.sv` 中 `hand_pix` 在声明前使用（仿真会报隐式声明错误）；已把声明前移，30 个 RTL/Testbench 文件全部编译通过。
- 最新比特流已重新综合/实现/生成：`top_cam_game.bit`，3,825,992 bytes，WNS **+8.747 ns**，全约束满足，0 routing error。

**遗留问题**
- `说明/` 为中文目录名，与 `repo_conventions.md` 的英文路径规则冲突；`script2/` 与 `scripts/` 功能重复。
- 根 `README.md` 目前是整理说明，不是可供队友直接复现的入口文档。
- 旧 `web-game/` 被本次重构整体移除；若仍需浏览器演示，应从历史提交恢复。

---

---

### 2026-10-25 | A（平台与集成） | DeepSeek Harness（qwen3.8-flash / glm-5.3 多模型）

**目标**：给光流版游戏核心建立"能自己跑起来"的验证环境，并能判断核心逻辑是否正确。

**提问（原样粘贴）**

```
教我怎么创建工程然后在vivado里面跑（附 game_core.sv 路径）
```

**AI 执行过程（可核查）**

1. 读 `game_core.sv` 后指出：`TICK_DIV=833333`（50 MHz→60 Hz）下每拍要等 80 万时钟沿，
   仿真必须用**参数覆盖**加速，否则跑不动；先做行为仿真再谈上板。
2. 产出 `tb_game_core.sv`（`TICK_DIV=8`，含战况打印与关键信号监视），本机无 Vivado 时
   改用 ModelSim 10.5b 批处理验证。
3. 定位 4 个真实故障（见下表），最终编译 0 error、仿真 82 µs 跑完全流程
   （得分 70→200、掉命 6→5、UFO 出现、暂停/恢复均触发）。

**纠错轨迹（重要）**

| # | 现象 | 根因 | 处理 |
| --- | --- | --- | --- |
| 1 | `vlog` 报 `sqlite3_open ... unable to open database file`，路径乱码 | 工作目录在中文用户名下，ModelSim 为 ANSI 构建 | 换到纯英文目录 `C:\msim_game` |
| 2 | 极简模块也报 `Error loading design` + `FileWatch(fileName)` | `TEMP/TMP` 指向中文目录 | 把 `TEMP/TMP` 覆盖为英文子目录后正常 |
| 3 | `vsim-3694`：`(.*)` 找不到 `clk_sys` 端口 | TB 里时钟命名 `clk`，与 DUT 端口 `clk_sys` 不匹配（该错误只在加载期报，编译期不报） | TB 信号改名为 `clk_sys` |
| 4 | 仿真跑不完 | `TICK_DIV` 未覆盖 | 例化时 `#(.TICK_DIV(8))`，逻辑不变仅提速 |

**产出物**：`sim/tb_game_core.sv`（初版）、ModelSim 仿真日志。

---

### 2026-10-29 | A/B/C（提交材料整理） | DeepSeek Harness（glm-5.3 / deepseek-v4.1-flash）

**目标**：按官方《选题指南（AMD）》3.3 要求，把仓库整理成可提交结构，并补齐
综合与实现报告、技能包、设计报告、架构图。

**提问（原样粘贴，按时间顺序）**

```
我们现在交作品还缺什么东西还需要怎么弄
你就直接写drawio的代码然后我打开drawio就能看的那种
我的仓库在d盘啊D:\fpga\fpga_space_invaders
11yue4hao截止
ai协作的那个你是不是还没写
```

**人工决策（AI 只给选项，不替用户定）**

| 决策点 | 选项 | 结论 |
| --- | --- | --- |
| 提交哪个版本 | 肤色版 / **光流版** / 两个都交 | **光流版**（`cam_game_optiflowverison`），肤色版保留为对照 |
| 仓库结构 | 保持 `说明/` / **根目录建官方结构** / 重构 | **根目录建官方结构**，材料复制同步，原工作区不动 |

**AI 执行过程（可核查）**

1. 解析 28 页指南 PDF，确认所属赛道（3.3 自主选题·初级组）与提交清单；
2. 在仓库根目录建立 `src/ sim/ build/ board/ data/ skill/ report/ docs/`，
   源码从 `cam_game_optiflowverison/src/rtl` 复制（20 个文件），约束与 bit 从该工程取；
3. 写 `build/build.tcl`（含 `hdmi_pll` IP 自动生成）并在真工程上跑一次完整构建，
   产出 bitstream 3.65 MB 与 11 份报告；
4. 跑仓库 testbench：**14/14 断言全 PASS**，日志存 `sim/sim_log.txt`；
5. 产出 5 张 drawio 图（架构/数据流/时钟域/主FSM/手势FSM）、`skill/README.md`（8 条）、
   `report/report.md`、`docs/*.md`，并重写根 `README.md`。

**纠错轨迹（重要）**

| # | AI 的错误 / 缺陷 | 发现方式 | 修正 |
| --- | --- | --- | --- |
| 1 | 一直在 C 盘副本 `C:\FPGA\space_invaders_fpga` 上作业 | 用户指出"我的仓库在d盘" | 全部材料迁到 `D:\fpga\fpga_space_invaders` 根结构 |
| 2 | 依据"逐行注释版"副本写文档，与仓库真源码版本不一致 | 对比 `game_core.sv` 行数（377 vs 571） | 以仓库 `cam_game_optiflowverison/src/rtl` 为准重建 |
| 3 | 注释版 XDC 行尾 `#` 注释导致 53 个引脚约束全部失效（DRC NSTD-1/UCIO-1，bitgen 失败） | bitstream 阶段报错 | 清理行尾注释并做**前后计数校验**（116 条命令/53 引脚零丢失） |
| 4 | 生成 XDC 清理脚本时按整行注释处理，误把命令并进注释行 | 输出行数与命令数对不上 | 改为"非注释行截断首个 `#`"+ 计数断言，先恢复备份再重做 |
| 5 | Vivado 批处理在布线后报告阶段卡死（子进程占用 15 GB、CPU 空转 20 min） | 日志停在 `Bitgen Completed` 不动 | 终止进程，改用已生成的 `*_routed.dcp` 单独导出报告 |
| 6 | 用 `Set-Content -Encoding UTF8` 写 Tcl 带 BOM，Vivado 报 `invalid command name "锘縮et"` | 报告脚本第一行就失败 | 改用 `UTF8Encoding($false)` 无 BOM 写入 |
| 7 | 根 `.gitignore` 含 `/build/ /sim/ /scripts/`，会把新提交目录整个排除 | `git check-ignore` 逐个验证 | 重写为只忽略构建产物，14 个必备文件全部可提交 |
| 8 | `说明/docs/architecture.md` 是第零阶段规划稿（肤色版/AXI-Stream），与提交版不符 | 与 RTL 模块清单对照 | 在文首加版本声明，指向 `docs/architecture.md` 为准 |

**采纳 / 否决**

- 采纳：官方目录结构、"一条命令出 bit + 报告"、技能包按"真实踩坑"写（禁写教科书条目）；
- 否决：同时提交两个版本（工作量翻倍，且指南推荐只选其一）；
- 保留意见：`hold` 余量仅 +0.090 ns，报告中如实列为风险而非隐去。

**产出物**：根目录提交结构（`src/ sim/ build/ board/ data/ skill/ report/ docs/`）、
`build/build.tcl`、`build/report/`（11 份）、`sim/sim_log.txt`（14 PASS）、
`skill/README.md`（8 条）、`report/report.md`、`docs/diagrams/*.drawio`。

**待办**：板级照片/视频（10 项，清单见 `board/README.md`）、确认官网提交入口与截止时刻、
`git commit/push`。

---

## 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-10-11 | 建立日志，记录第零阶段 AI 协作全过程与 5 条纠错轨迹 | A |
| v1.1 | 2026-10-11 | 追加器件冻结（Artix-7）决策记录与架构调整说明 | A |
| v1.2 | 2026-10-17 | 游戏 v2 上板、OV7725 摄像头手势、肤色标定与小窗预览；记录 9 条关键纠错 | C/A |
| v1.3 | 2026-10-17 | 肤色标定方案落地：上电无默认肤色、key1 全屏采样、160×160 ROI、中点±12、合理性检查、小窗预览 | C/A |
| v1.4 | 2026-10-17 | 复核目录重构、恢复构建源、相对化 xpr 路径、加入 sim_1，并记录最新构建验证 | C/A |
| v1.5 | 2026-10-17 | 修复 top_cam_game 中 hand_pix 声明顺序，完成全量 xvlog 与重新构建验证 | C/A |
| v1.6 | 2026-10-25 | 为光流版建立可仿真验证环境（TICK_DIV 参数覆盖），记录中文路径/隐式端口连线等 4 条纠错 | A |
| v1.7 | 2026-10-29 | 官方 3.3 提交结构落地、真实构建（WNS +3.428ns）、14 断言全过、技能包 8 条、5 张架构图；记录 8 条纠错 | A/B/C |