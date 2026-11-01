# 交接说明（截至 2026-10-30）

> 给队友的现状速览。**5 分钟读完**，知道现在在哪、还差什么、谁做什么。
> 截止：**2026-11-04**（剩 5 天）

---

## 1. 一句话现状

**作品已能一条命令构建出可烧写的 bitstream，提交结构已按官方要求落地并推上 GitHub。**
剩下的是"板级实拍证据 + 确认提交入口"，代码不用再大改。

| 项 | 状态 |
|---|---|
| 源码（光流版 20 个文件） | ✅ 完成，已跑通综合/实现/bitstream |
| 仿真验证 | ✅ 14/14 断言全过（`sim/sim_log.txt`） |
| 综合与实现报告 | ✅ 11 份实测报告（`build/report/`） |
| 提交目录结构（官方 3.3） | ✅ 已建并推送 |
| 技能包（15 分项） | ✅ 8 条（`skill/README.md`） |
| 设计报告 | ✅ 正文已成稿（`report/report.md`），缺团队信息 |
| 架构图/数据流图 | ✅ 5 页 drawio（`docs/diagrams/`） |
| **板级照片/视频** | ❌ **缺（硬性要求，见第 6 节）** |
| **确认提交入口与时刻** | ❌ 缺 |
| Git 推送 | ✅ 已完成（commit `4045234`，86 个文件） |

---

## 2. 提交哪个版本

**以光流版为准**：`is-it-possible-to-ai-it-perfect/cam_game_optiflowverison`

| 版本 | 位置 | 定位 |
|---|---|---|
| **光流版（提交）** | `cam_game_optiflowverison` | LK 光流 + 投票漏桶，主提交 |
| 肤色版 | `is-it-possible-to-ai-it-perfect/cam_game` | 肤色二值化+质心，对照/备选 |
| 按键版 | `src/top_button_game.sv` | 无摄像头演示 |

> 两版游戏本体**参数不可混用**（血量/射速/移速不同），别把一版的 `game_core` 配到另一版顶层。

## 3. 仓库结构（两套并存，别搞混）

```
仓库根/
├── README.md / LICENSE / .gitignore   ← 提交用（官方结构）
├── src/ sim/ build/ board/ data/ skill/ report/ docs/   ← 提交用（官方结构）
│
├── fpga_space_invaders/               ← 原 Vivado 工程（肤色版，日常开发用）
├── is-it-possible-to-ai-it-perfect/   ← 原工程（光流版/肤色版/按键版，Codex 产出）
└── 说明/                              ← 开发过程文档（协作日志、接口规范、脚本、Python）
```

- **提交材料只在根目录那 8 个文件夹里**，别往 `说明/` 里塞提交物；
- 根目录 `src/` 是光流版源码的**副本**，源工程改动后需要重新同步一次；
- `说明/docs/architecture.md` 是第零阶段规划稿（肤色路线），**正式架构看根目录 `docs/architecture.md`**。

## 4. 关键数据（Vivado 2026.1 实测）

| 指标 | 值 |
|---|---|
| 器件 / 顶层 | `xc7a100tfgg484-2` / `top_cam_game` |
| LUT / FF | 16,265（25.65%）/ 6,800（5.36%） |
| BRAM / DSP | 48.5（**35.93%**）/ 12（5.00%） |
| 时序 | WNS **+3.428 ns**、WHS +0.090 ns（14,175 端点，0 失败） |
| 功耗 | 0.282 W（动态 0.182 + 静态 0.100） |
| bitstream | 3.65 MB |
| 三时钟 | 摄像头 24 MHz / 系统 50 MHz / 显示 25 MHz（MMCM 同源） |
| 仿真 | 48.7 µs，14 条断言全 PASS |

**结论一句话**：瓶颈在 BRAM（灰度帧双缓冲 150 KB），不在逻辑；时序余量充足。

## 5. 常用命令

```powershell
# 构建（一条命令出 bit + 全部报告）
cd D:\fpga\fpga_space_invaders
vivado -mode batch -source build/build.tcl

# 仿真（Vivado GUI 里）
#   Add Sources → sim/tb_game_core.sv → Run Behavioral Simulation → Tcl: run -all

# 推送（代理已配好，需 Clash 运行）
git add -A ; git commit -m "..." ; git push
```

> 若 Clash 关闭导致 push 失败：`git config --global --unset http.proxy`（https 同理）。

## 6. 待办分工（到 11/4）

| 优先级 | 事项 | 谁 | 说明 |
|---|---|---|---|
| 🔴 P0 | **板级照片/视频** | 谁有板谁拍 | `board/README.md` 有 10 项清单；**必须拍到"挥手时画中画变红/绿"**（证明光流在跑） |
| 🔴 P0 | **确认提交入口/截止时刻** | 队长 | fpgachina.cn：系统上传还是邮件？zip 还是仓库链接？11/4 几点？ |
| 🟡 P1 | 报告补团队信息 | 队长 | `report/report.md` 开头表格：队名/学校/成员分工 |
| 🟡 P1 | `data/README.md` 板级比对表 | 拍摄后 | 把实测现象与仿真参考逐项打勾 |
| 🟢 P2 | 决赛一页英文海报 | 暂缓 | 进决赛才需要，用 AMD 模板 |
| 🟢 P2 | V2 优化（可选） | 技术 | `lk_flow` 的 6 个累加 FIFO 改同步复位→可映射 BRAM，省 FF |

## 7. 已经踩过并修好的坑（别再踩）

| # | 坑 | 后果 | 现在的状态 |
|---|---|---|---|
| 1 | XDC 行尾 `#` 注释 | 53 个引脚约束全失效，bitgen 失败（DRC NSTD-1/UCIO-1） | 已清理并做计数校验，**新写 XDC 时注释必须单独成行** |
| 2 | 根 `.gitignore` 含 `/build/` `/sim/` | 提交材料被 git 排除，推不上去 | 已重写，只忽略构建产物 |
| 3 | 掩体位图变量下标 | 综合出巨型 MUX，实现阶段卡死 | 已改 `get_bunk_x` case 固定坐标 |
| 4 | 仿真直接用 `TICK_DIV=833333` | 跑不动 | testbench 用 `TICK_DIV=10` 覆盖 |
| 5 | Tcl 脚本带 BOM | Vivado 报 `invalid command name "锘縮et"` | 写 tcl 用无 BOM UTF-8 |
| 6 | 中文路径跑 ModelSim | `sqlite3_open` 失败 / `Error loading design` | 工作目录与 `TEMP` 都用纯英文 |

## 8. 光流版操作方式（上板）

- 挥手左右 → 炮台左右；停手 → 停
- **key2** 开始/暂停/继续，**key3** 重开
- 右上角画中画：红=向左、绿=向右、灰=静止（调试与演示的核心证据）
- 环境要求：光照充足、背景有纹理（纯墙光流会失效）

## 9. 已知不足（报告里已如实写明）

1. hold 余量仅 +0.090 ns，换更快像素时钟需重新收敛；
2. `lk_flow` 6 个累加 FIFO 因异步复位被拆成寄存器实现（FF 偏多）；
3. 光流对光照/纹理敏感，无自动曝光；
4. 未接音频（PWM 音效模块有设计未接入，不影响主功能）。

---

## 10. AI 协作记录（2026-10-25 ~ 10-30 摘要）

> 完整原文（含提示词全文、工具调用、逐条核对）见 **[`ai_collaboration.md`](ai_collaboration.md)**。
> 本节是压缩版，供队友快速了解"这段时间 AI 做了什么、错在哪、最后留下什么"。

### 10.1 协作方式

| 项 | 内容 |
|---|---|
| 工具 | **DeepSeek Harness**（多模型切换：`qwen3.8-flash` / `glm-5.3` / `deepseek-v4.1-flash`） |
| 配合工具 | Vivado 2026.1（批处理构建）、ModelSim 10.5b（仿真）、Python（画图/PDF/校验脚本） |
| 分工原则 | **人定目标与验收标准，AI 出代码/脚本/文档草稿，一切以工具实测输出为准** |
| 判定规则 | AI 的说法若与工具输出冲突，**以工具输出为准**；AI 的"完成"必须附可核查证据（日志/报告/文件） |

### 10.2 时间线（三天，三个阶段）

| 日期 | 目标 | 提示词（原文） | 主要产出 |
|---|---|---|---|
| 10-25 | 让游戏核心能跑起来 | 「教我怎么创建工程然后在vivado里面跑」 | `tb_game_core.sv`（`TICK_DIV` 参数覆盖）、ModelSim 仿真通过 |
| 10-29 | 按竞赛指南整理提交材料 | 「我们现在交作品还缺什么东西还需要怎么弄」<br>「你就直接写drawio的代码然后我打开drawio就能看的那种」<br>「我的仓库在d盘啊…」 | 官方 3.3 结构、`build/build.tcl`、11 份报告、5 张图、技能包 8 条、设计报告 |
| 10-30 | 推送到远端 | 「我怎么push」「你能帮我push上去吗」 | 远端 `main` → `4045234`（86 文件），代理/认证排障 |

### 10.3 纠错轨迹汇总（13 条，全为真实发生）

**A. 仿真环境（10-25）**

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | `sqlite3_open ... unable to open database file`，路径乱码 | ModelSim 为 ANSI 构建，中文路径被错误编码 | 工作目录换纯英文 |
| 2 | 极简模块也 `Error loading design` + `FileWatch(fileName)` | `TEMP/TMP` 指向中文目录 | 覆盖 `TEMP/TMP` 为英文目录 |
| 3 | `vsim-3694`：`(.*)` 找不到 `clk_sys` | TB 信号名 `clk` ≠ DUT 端口 `clk_sys`（只在加载期报错） | TB 改名 `clk_sys` |
| 4 | 仿真跑不完 | `TICK_DIV=833333` 未覆盖 | 例化时 `#(.TICK_DIV(10))` |

**B. 提交材料与构建（10-29）**

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 5 | AI 一直在 C 盘副本作业 | 未确认仓库真实位置 | 用户指出后全部迁到 `D:\fpga\fpga_space_invaders` |
| 6 | 文档与仓库源码版本不符（377 行 vs 571 行） | 依据"逐行注释版"副本写文档 | 以仓库 `cam_game_optiflowverison/src/rtl` 为准重建 |
| 7 | bitgen 失败（DRC NSTD-1 / UCIO-1，53 个引脚全失效） | 注释版 XDC 行尾 `#` 被 Tcl 当参数 | 清理行尾注释 + 计数校验（116 命令/53 引脚零丢失） |
| 8 | 清理脚本误把命令并进注释行 | 按整行注释处理，未区分命令/注释 | 改"非注释行截断首个 `#`" + 计数断言，先恢复备份重做 |
| 9 | Vivado 批处理在布线后报告阶段卡死（15 GB / CPU 空转 20 min） | 子进程生成全量报告时异常 | 终止；改用 `*_routed.dcp` 单独导出报告 |
| 10 | Vivado 报 `invalid command name "锘縮et"` | PowerShell 写 Tcl 带 UTF-8 BOM | 用 `UTF8Encoding($false)` 无 BOM 写入 |
| 11 | 提交目录被 git 排除 | 根 `.gitignore` 含 `/build/ /sim/ /scripts/` | 重写为只忽略构建产物，14 项关键文件逐个 `git check-ignore` 验证 |
| 12 | `说明/docs/architecture.md` 与实现不符 | 该文档是第零阶段肤色路线规划稿 | 文首加版本声明，指向根 `docs/architecture.md` |

**C. 推送（10-30）**

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 13 | push 失败：`Connection was reset` → `schannel handshake failed` → `ServicePointManager 不支持 socks5h` → `User cancelled dialog` | 四层原因：①Clash 在跑但**系统代理关闭**；②HTTP 代理到 github 不稳定；③**GCM 是 .NET，不支持 socks5**；④误改 GCM provider 致认证失效 | 逐步定位后：git 走 HTTP 代理 + 恢复默认 provider + **复用已缓存 OAuth 凭据**（用 `git credential fill` 先验证）→ 推送成功 |

### 10.4 人工决策（AI 只提供选项，不替人拍板）

| 决策点 | 选项 | 结论 |
|---|---|---|
| 提交哪个版本 | 肤色版 / **光流版** / 两个都交 | **光流版**（肤色版作对照） |
| 仓库结构 | 保持 `说明/` / **根目录官方结构** / 重构 | **根目录官方结构**，原工作区不动 |
| 是否同时交两版 | 是 / **否** | **否**（工作量翻倍且指南建议只选其一） |
| `hold` 余量仅 +0.09 ns 是否写进报告 | 隐去 / **如实写** | **如实写**，并列为已知风险 |

### 10.5 这段协作沉淀出的可复用产物

| 产物 | 位置 | 价值 |
|---|---|---|
| 技能包 8 条（S1~S8） | `skill/README.md` | 每条含"适用场景/做法/已验证效果/失效条件"，别人可直接套 |
| 一键构建脚本 | `build/build.tcl` | 评委可原样复现出 bitstream |
| 5 张架构图 | `docs/diagrams/*.drawio` | 可编辑、可导 PNG |
| 设计报告正文 | `report/report.md` | 含优化对比与失败分析 |
| 本交接文档 | `说明/docs/handover.md` | 队友 5 分钟上手 |

### 10.6 后续怎么继续记（给队友的约定）

每次与本类工具协作后，按下面 5 行补一条到 `ai_collaboration.md`（**禁止事后编造**）：

```
### YYYY-MM-DD | 角色 | 工具与模型
**目标**：
**提问（原样粘贴）**：       ← 用代码块，保留原始中文与错别字
**AI 执行过程（可核查）**：   ← 命令、报错原文、文件路径
**纠错轨迹**：               ← 表格：# / 现象 / 根因 / 处理（失败也要写）
**产出物**：                 ← 文件路径，可让评委点开核对
```

评分看的是"**失败与纠错轨迹**"，不要只写成功案例。

---

**有疑问先看**：`README.md`（总览）→ `docs/architecture.md`（架构/状态机/时钟域）→
`docs/synthesis_report.md`（实测数据）→ `skill/README.md`（踩坑经验）。