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

## 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-10-11 | 建立日志，记录第零阶段 AI 协作全过程与 5 条纠错轨迹 | A |
| v1.1 | 2026-10-11 | 追加器件冻结（Artix-7）决策记录与架构调整说明 | A |