# 第零阶段交付清单（Phase 0 Checklist）

| 项目 | 内容 |
| --- | --- |
| 截止日 | **2026-10-11（本周周日）** |
| 主责 | A（平台与集成） |
| 参与 | A / B / C 全体 |
| 状态 | 进行中 -> 完成后改为「已关闭」并打标签 `v0.1-w0` |

第零阶段只做四件事：**定手势、定时钟与接口、装软件、定规矩**。
本阶段不写游戏逻辑、不做视觉算法，目的是让三个人可以**并行开工且互不阻塞**。

---

## 1. 交付物总览

| 编号 | 任务 | 交付物 | 主责 | 状态 |
| --- | --- | --- | --- | --- |
| P0-1 | 定义四种手势 | `docs/gesture_spec.md` v1.0 | B | ✅ 已完成 |
| P0-2 | 确认时钟频率与接口标准 | `docs/interface_spec.md` v1.0 | A | ✅ 已完成（第 2 节板卡待冻结） |
| P0-3 | 安装所需软件并验证 | `docs/environment_setup.md` + `scripts/check_env.ps1` + `requirements.txt` | A | ✅ 已完成（自检全绿） |
| P0-4 | 约定仓库使用规范 | `docs/repo_conventions.md` v1.0 | A | ✅ 已完成 |
| P0-5 | 交付物评审与冻结 | 三人确认签字（在本文件勾选） | 全员 | ⬜ 待评审 |
| P0-6 | 首次提交并打标签 | Git commit + tag `v0.1-w0` | A | ⬜ 待执行 |

---

## 2. P0-1 四种手势（对照 `docs/gesture_spec.md`）

- [x] 选定四种手势：**G1 左移 / G2 右移 / G3 射击 / G4 开始**
- [x] 每种手势给出可计算特征：`feat_cx / cy / area / w / h / open / vx`
- [x] 给出量化阈值（进入 192 / 退出 256、张开 480 / 握拳 300、面积 2000–120000）
- [x] 定义迟滞（hysteresis）避免分界线抖动
- [x] 定义去抖帧数（进入 5 帧 / 退出 3 帧）与冷却（射击 300 ms / 开始 2000 ms）
- [x] 定义命令编码（`cmd_valid` + `cmd[3:0]` 独热）
- [x] 定义验收标准（成功率 ≥ 90%、误触发 ≤ 1 次/分钟、延迟 ≤ 20 ms）
- [x] 确认**所有阈值走 AXI4-Lite 寄存器**，不硬编码

**评审确认**：A ⬜　B ⬜　C ⬜

---

## 3. P0-2 时钟与接口（对照 `docs/interface_spec.md`）

- [x] 系统时钟 `clk_sys = 100 MHz`
- [x] 像素时钟 `clk_pix = 25.2 MHz`（VGA 640×480@60）
- [x] 游戏步进 `tick_60hz`（使能脉冲，非新时钟）
- [x] 摄像头接口：**DVP 8-bit + SCCB/I2C**，640×480@30，明确排除 USB
- [x] 显示接口：**VGA 640×480@60**（4-4-4 电阻网络），备选 HDMI
- [x] 片内总线：AXI4-Stream（视频，32 bit）+ AXI4-Lite（寄存器，100 MHz）
- [x] 复位规范：低有效 `rst_n`，异步置位/同步释放，每域一个同步器
- [x] 分辨率链：采集 640×480 → 视觉 320×240 → 游戏 320×240 → 显示 640×480
- [x] CDC 方案：异步 FIFO（视频）、双触发器 + 单比特 valid（特征/命令）
- [x] 寄存器映射冻结（基地址 `0x43C0_0000`，见第 5.3 节）
- [x] 模块端口契约冻结（8 个模块的输入输出与时钟域）
- [x] 延迟预算冻结（帧→命令 ≤ 20 ms，命令→画面 ≤ 33 ms）
- [x] **器件系列冻结为 Artix-7**（XC7A100T 首选，`interface_spec.md` 已升 v1.1）；具体开发板型号待采购确认

**评审确认**：A ⬜　B ⬜　C ⬜

---

## 4. P0-3 软件安装（对照 `docs/environment_setup.md`）

本机实测（2026-10-11）：

- [x] Git 2.56.0.windows.2
- [x] Python 3.13.5（**注意：统一用 `py -3`，裸 `python` 是 Store 占位程序**）
- [x] Python 图像库：numpy 2.5.4 / opencv-python 5.0.0 / scipy 1.18.1 / matplotlib 3.11.2 / pillow 12.3.0 / scikit-image 0.26.0
- [x] cocotb 2.1.0（验证用，可选）
- [x] Node.js v24.19.0（仅 web 原型）
- [x] VS Code 1.141.0（winget 用户级安装）
- [x] Vivado 2026.1（`D:\fpga\2026.1\Vivado\bin\vivado.bat`，**未加 PATH**，用绝对路径调用）
- [x] Vitis / Vitis HLS 2026.1
- [x] `scripts/check_env.ps1` 自检**全部必需项 PASS**
- [x] VS Code 扩展安装完成（Verilog/Python/Ruff/Pylance/GitLens/Markdown；Tcl 扩展已下架）
- [ ] 全员在自己机器上跑通 `check_env.ps1`（A/B/C 各自勾选）

**自检命令**

```powershell
cd D:\fpga\fpga_space_invaders
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_env.ps1
```

**评审确认**：A ⬜　B ⬜　C ⬜

---

## 5. P0-4 仓库规范（对照 `docs/repo_conventions.md`）

- [x] 目录结构冻结（`docs/ src/ sim/ constraints/ build/ scripts/ board/ data/ metrics/ skill/ report/`）
- [x] 命名规范冻结（路径全英文小写 + 数字 + `_` + `-`；RTL `lower_snake_case`）
- [x] 分支模型冻结（`main` / `dev` / `feature/*` / `fix/*` / `doc/*`）
- [x] 提交规范冻结（Conventional Commits）
- [x] PR 模板与合入条件
- [x] 数据与大文件规则（大文件不入库）
- [x] AI 协作记录规范（`docs/ai_collaboration.md`）
- [x] 集成交付节奏（每日 22:00 / 每周六 20:00 / 每周日 20:00 / 每周日 22:00）
- [ ] 全员确认并遵守（A/B/C 各自勾选）

**评审确认**：A ⬜　B ⬜　C ⬜

---

## 6. 遗留问题（移交第 1 周）

| 编号 | 问题 | 负责人 | 期限 |
| --- | --- | --- | --- |
| R1 | ~~器件系列冻结~~ ✅ 已定为 **Artix-7**（XC7A100T 首选）；仅剩具体开发板型号待采购确认 | A | ✅ 2026-10-11 |
| R2 | 摄像头模组选型与采购（DVP + SCCB） | A | 第 1 周 |
| R3 | VGA 输出硬件（电阻网络 DIY vs 现成模块） | A | 第 1 周 |
| R4 | MMCM 能否精确产生 25.175 MHz（否则调整容差） | A | 第 1 周 |
| R5 | 手势阈值现场标定，验证 `open` 判别是否收敛 | B | 第 1–2 周 |
| R6 | ~~仓库中残留的中文/占位文件名清理~~ **已完成**（见第 7 节） | A | ✅ 2026-10-11 |
| R7 | 全员机器跑通 `check_env.ps1` | A/B/C | 第 1 周 |

---

## 7. 仓库卫生检查（发现的问题）

| 文件 | 问题 | 处理 |
| --- | --- | --- |
| ~~`新建 DOC 文档.doc`~~ | 文件名含中文，违反命名规范；已确认为 WPS 空模板（无正文内容） | ✅ 已 `git mv` 为 `report/report_draft.doc` |
| ~~`src/新建 PPT 演示文稿.ppt`~~ | 同上，且 PPT 不该放在 `src/`；已确认为 WPS 空模板 | ✅ 已 `git mv` 为 `report/slides_draft.ppt` |
| `src/.gitkeep`、`board/.gitkeep` 等 | 占位文件，正常 | 保留 |
| `web-game/` | 浏览器原型，与 FPGA 主线并行存在 | 保留，需在 README 中说明其定位（算法验证 + 演示对比，非最终交付） |

**清理原则**：先 `git mv` 重命名保留历史；确认无内容后再删除。

---

## 8. 关闭条件

本阶段视为关闭，需同时满足：

1. P0-1 ~ P0-4 四份文档均已被 **A/B/C 三人** 阅读并确认（第 2–5 节勾选完成）。
2. 三人在各自机器上运行 `check_env.ps1` 均无 FAIL。
3. 中文/占位文件名问题已处理（第 7 节）。
4. 提交并打标签：`git tag v0.1-w0 && git push origin v0.1-w0`。

---

## 9. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-10-11 | 首次建立第零阶段清单，记录四项交付物与遗留问题 | A |