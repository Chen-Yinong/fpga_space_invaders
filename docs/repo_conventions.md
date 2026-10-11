# 仓库使用规范（Repository Conventions）

| 项目 | 内容 |
| --- | --- |
| 阶段 | 第零阶段（WP0）冻结项 |
| 版本 | v1.0 |
| 生效日期 | 2026-10-11（周日） |
| 主责 | A（平台与集成） |
| 适用对象 | A / B / C 全体成员 + 所有 AI 协作产出 |
| 仓库地址 | https://github.com/Chen-Yinong/fpga_space_invaders |

本文件约定**目录、命名、分支、提交、评审、数据与 AI 记录**的规则。
目的只有一个：**任何人 clone 下来都能一条命令重建整个工程，并且三个月后还看得懂。**

---

## 1. 目录结构（冻结）

```
fpga_space_invaders/
├─ README.md                  # 项目总览、构建与复现入口（务必保持可执行）
├─ LICENSE                    # MIT 或 Apache-2.0
├─ docs/                      # 全部设计文档
│   ├─ architecture.md        # 系统架构与数据流
│   ├─ gesture_spec.md        # 四种手势定义（唯一权威）
│   ├─ interface_spec.md      # 时钟/接口/寄存器/坐标（唯一权威）
│   ├─ repo_conventions.md    # 本文件
│   ├─ environment_setup.md   # 软件安装与验证
│   ├─ phase0_checklist.md    # 第零阶段交付清单
│   ├─ hardware_setup.md      # 板卡、接线、供电
│   ├─ test_plan.md           # 测试计划与用例
│   └─ ai_collaboration.md    # AI 协作日志
├─ src/
│   ├─ rtl/                   # 手写 RTL（Verilog/SystemVerilog）
│   ├─ hls/                   # Vitis HLS 源码
│   ├─ ps/                    # PS 侧代码（仅配置/日志）
│   └─ ip/                    # IP 生成脚本或 .xci（生成物不入库）
├─ sim/                       # Testbench、cocotb 用例、测试向量
├─ constraints/               # XDC 约束
├─ build/                     # Vivado 工程与构建脚本（生成物不入库）
├─ scripts/                   # 自动化脚本（构建、检查、转换）
├─ board/                     # 上板照片、接线图、比特流校验信息
├─ data/                      # 小型测试数据（大文件走 LFS）
├─ metrics/                   # 指标与证据
│   ├─ metrics.csv            # 延迟/帧率/资源汇总
│   ├─ logs/                  # 综合实现日志摘要
│   ├─ scripts/               # 指标提取脚本
│   └─ evidence/              # 波形截图、ILA 截图、对比图
├─ skill/                     # 可复用 Skill 与提示词模板
├─ report/                    # 设计报告、PPT、演示视频
└─ web-game/                  # 浏览器原型（用于算法验证与演示对比）
```

**规则**

1. 目录与文件名**只允许**英文小写字母、数字、下划线 `_`、连字符 `-`。
   **中文只出现在文件内容里**，绝不出现在路径中。
2. 每个目录必须有用途，**不允许**随手建 `temp/`、`新建文件夹/`、`test2/`。
3. 新增顶层目录必须先在群里说明并更新本文件。

---

## 2. 命名规范（冻结）

| 对象 | 规范 | 正例 | 反例 |
| --- | --- | --- | --- |
| 目录 / 文件 | `lower_snake_case` | `gesture_fsm.v`, `vga_timing.v` | `GestureFSM.v`, `手势.v` |
| Verilog 模块名 | `lower_snake_case`，与文件名一致 | `gesture_fsm` | `gestureFSM` |
| 实例名 | `u_<模块名>` | `u_gesture_fsm` | `inst1` |
| 信号 / 端口 | `lower_snake_case` | `feat_cx`, `cmd_valid` | `FeatCx`, `featcx` |
| 低有效信号 | 后缀 `_n` | `rst_n`, `cs_n` | `nrst` |
| 时钟 | 前缀 `clk_` | `clk_sys`, `clk_pix` | `clk2`, `clock` |
| 参数 | `UPPER_SNAKE_CASE` | `PLAYER_SPEED` | `playerSpeed` |
| 本地常量 | `localparam` + `UPPER_SNAKE_CASE` | `localparam IDLE = 2'd0;` | `define IDLE 0` |
| 状态机状态 | `S_<NAME>` | `S_IDLE`, `S_MOVE_LEFT` | `state0` |
| Python | `lower_snake_case.py`，函数/变量 `snake_case` | `golden_model.py` | `GoldenModel.py` |
| Tcl | `lower_snake_case.tcl` | `create_project.tcl` | `CreateProject.TCL` |
| 约束文件 | `top.xdc`、`<模块名>.xdc` | `vga_timing.xdc` | `约束1.xdc` |

**编码风格硬性要求**

1. 一个文件一个模块；模块名 = 文件名（`gesture_fsm.v` 里是 `module gesture_fsm`）。
2. 端口声明一律用 `ANSI` 风格，`input wire` / `output reg`，每个端口一行。
3. 缩进 **2 空格**，禁止 Tab；行宽 <= 100 字符。
4. 时序逻辑统一 `always @(posedge clk_sys or negedge rst_n)`，**不允许**在时序块里混用阻塞赋值做寄存器。
5. 状态机用 `localparam` 定义状态，用三段式或两段式，**禁止**同一个 `always` 里既算次态又算输出。
6. 跨时钟域代码必须加注释块：`// CDC: <源时钟> -> <目标时钟>, 方法: <同步器/FIFO>, 约束: <xdc 行号>`。
7. 每个模块头部必须有注释：模块名、功能、作者、日期、版本、输入输出说明。
8. 禁止 `#delay` 出现在可综合代码里（仅 Testbench 可用）。

---

## 3. 分支模型（冻结）

| 分支 | 用途 | 规则 |
| --- | --- | --- |
| `main` | **可构建、可复现**的稳定版本 | 只接受 PR 合入；每次合入必须能通过构建脚本 |
| `dev` | 集成分支，每周集成点 | A 负责合入，周日前必须可用 |
| `feature/<模块>-<简述>` | 个人功能开发 | 例：`feature/gesture-fsm`、`feature/vga-timing` |
| `fix/<简述>` | 修 bug | 例：`fix/axis-tready-backpressure` |
| `doc/<简述>` | 纯文档 | 例：`doc/phase0-spec` |

**工作流**

1. 从 `dev` 拉功能分支：`git switch -c feature/gesture-fsm dev`
2. 小步提交，本地 `git pull --rebase` 保持线性历史
3. 功能自测通过（仿真 + lint）后提 PR 合入 `dev`
4. 每周集成通过后，A 把 `dev` 合入 `main` 并打标签：`git tag v0.1-w1`

**禁止事项**

- ❌ 直接 push 到 `main`
- ❌ 用 `git push --force` 到 `main` / `dev`
- ❌ 提交生成物（`.bit`、`.dcp`、`.log`、`.jou`、`xsim.dir/`、`build/`）
- ❌ 提交大于 10 MB 的单个文件（走 LFS 或放本地）
- ❌ 提交编译器/IDE 个人配置（`.vscode/settings.json` 中的个人绝对路径除外，需加 `.gitignore`）

---

## 4. 提交信息规范（冻结）

采用 **Conventional Commits**，格式：

```
<type>(<scope>): <简要描述>

<可选：为什么这么改、影响范围、验证方式>
```

| type | 含义 |
| --- | --- |
| `feat` | 新功能（新模块、新寄存器） |
| `fix` | 修 bug |
| `docs` | 只改文档 |
| `refactor` | 重构，不改行为 |
| `sim` | 测试/仿真相关 |
| `build` | 构建脚本、Makefile、Tcl |
| `ci` | CI/工作流 |
| `chore` | 杂项 |

**scope 取值**：`env`、`rtl`、`hls`、`ps`、`sim`、`constraints`、`docs`、`metrics`、`script`。

**示例**

```
feat(rtl): add gesture_fsm with hysteresis and fire cooldown
fix(sim): correct tlast alignment in cam_capture testbench
docs(docs): freeze gesture spec v1.0 and interface spec v1.0
build(script): add vivado project rebuild script
```

**描述语言**：type/scope 用英文，描述建议英文；如用中文，保持简短短语，不要写整句。

---

## 5. Pull Request 规范（冻结）

PR 标题遵循提交规范。PR 描述必须包含：

```markdown
## 变更内容
- ...

## 影响模块
- ...

## 验证方式
- [ ] 仿真通过（命令：...）
- [ ] 综合通过（WNS = ...）
- [ ] 上板验证（现象：...）

## 是否修改接口
- [ ] 否
- [ ] 是（已更新 docs/interface_spec.md，版本 vX.Y）
```

**合入前置条件**

1. 至少有 **1 名其他成员** review 通过。
2. 若改动涉及 `docs/gesture_spec.md` 或 `docs/interface_spec.md` 的冻结项，
   必须走对应文档的变更流程，PR 描述里贴上变更记录链接。
3. `scripts/check_env.ps1` 与构建脚本在该分支上能跑通。
4. 不引入新的未约束时钟域。

---

## 6. 数据与大文件规范（冻结）

| 类型 | 规则 |
| --- | --- |
| 手势数据集（原始视频） | **不入库**；本地保存，完整数据集用 Git LFS 或网盘，`data/README.md` 写明获取方式 |
| 小样本（每类 2–3 段，< 5 MB） | 允许入库，放 `data/gesture/<class>/` |
| ILA 波形、BMP 抓图 | 只提交**截图/摘要**（PNG），原始 `.wdb`/`.vcd` 不入库 |
| 比特流、`.dcp`、综合报告 | 不入库；只把**关键指标**写入 `metrics/metrics.csv`，日志摘要放 `metrics/logs/` |
| 演示视频 | 放 `report/` 或用外部链接，单文件 < 10 MB |
| Python 包 | `requirements.txt` 声明版本，禁止提交 `venv/`、`__pycache__/` |

`metrics/metrics.csv` 字段约定：

```
date,stage,metric,value,unit,note
2026-10-11,impl,wns,0.35,ns,clk_sys 100MHz
2026-10-11,synth,lut,4123,count,vision+game
```

---

## 7. AI 协作记录规范（冻结）

比赛评分含"大模型协作与技能包"15 分，**必须从第一天开始记录**。

1. 主日志：`docs/ai_collaboration.md`，按日期倒序或顺序追加，每条包含：
   - **日期 / 角色 / 工具与模型**
   - **提问（真实提示词，原样粘贴）**
   - **回答要点（摘要）**
   - **采纳/否决/纠错**：模型哪里错了、你是怎么发现的、最终怎么改
   - **产出物路径**（文件、脚本、波形）
2. **纠错轨迹比成功记录更重要**：必须记录"AI 给出错误方案 -> 我发现问题 -> 修正"的完整过程。
3. 方法论文档放 `skill/`，每个 Skill 一个目录，含 `README.md`（适用场景、输入输出、边界与不适用情况）。
4. 禁止伪造记录；禁止把 AI 输出直接当作最终结论而不做验证。

---

## 8. 构建与复现规范（冻结）

1. **禁止手工点 Vivado GUI 建工程**。工程必须由 Tcl 脚本重建：
   `vivado -mode batch -source scripts/create_project.tcl -tclargs <board>`
2. 每次提交前自检（本地）：
   ```powershell
   .\scripts\check_env.ps1          # 环境自检
   .\scripts\lint_rtl.ps1           # 或 iverilog/verilator 语法检查
   ```
3. 每个里程碑更新 `README.md` 的"复现步骤"，并至少在**一台干净机器**上验证过。
4. `.gitignore` 只增不删；要删必须先确认没有忽略掉必要文件。

---

## 9. 沟通与集成节奏（冻结）

| 时间 | 事项 |
| --- | --- |
| 每日 22:00 前 | 各自提交当天代码，`dev` 分支可构建 |
| 每周六 20:00 | A 合并 `dev`，跑完整构建 + 仿真，输出周报 |
| 每周日 20:00 | 组会：进度对齐、风险清单更新、下阶段任务分配 |
| 每周日 22:00 | 打标签 `vX.Y-wN`，归档 `metrics/metrics.csv` |

**风险登记**：风险清单统一维护在 `docs/architecture.md` 末尾或单独小节，每周组会更新状态。

---

## 10. 快速上手（新成员三步）

```powershell
git clone https://github.com/Chen-Yinong/fpga_space_invaders.git
cd fpga_space_invaders
.\scripts\check_env.ps1
```

然后阅读顺序：`README.md` -> `docs/interface_spec.md` -> `docs/gesture_spec.md` -> `docs/repo_conventions.md`。

---

## 11. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-10-11 | 首次冻结：目录、命名、分支、提交、PR、数据、AI 记录、构建与节奏规范 | A |