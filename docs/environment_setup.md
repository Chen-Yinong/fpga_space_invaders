# 环境与软件安装规范（Environment Setup）

| 项目 | 内容 |
| --- | --- |
| 阶段 | 第零阶段（WP0）冻结项 |
| 版本 | v1.0 |
| 冻结日期 | 2026-10-11（周日） |
| 主责 | A（平台与集成） |
| 自检脚本 | `scripts/check_env.ps1` |
| 依赖清单 | `requirements.txt` |

本文件规定**本机需要安装哪些软件、装在哪、怎么验证**。
新成员上手机器只需要做两件事：按第 2 节装齐软件，然后跑第 4 节的自检脚本。

---

## 1. 工具清单（本机实测结果，2026-10-11）

| 工具 | 要求版本 | 本机状态 | 安装位置 | 用途 |
| --- | --- | --- | --- | --- |
| Windows | Win 10/11 x64 | ✅ Windows 11 家庭版中文版 (Build 26200) | — | 宿主系统 |
| Git | >= 2.40 | ✅ 2.56.0.windows.2 | `D:\fpga\Git\cmd\git.exe` | 版本控制、GitHub 协作 |
| Python | 3.11 – 3.13 | ✅ 3.13.5 | `C:\Users\Strange\AppData\Local\Programs\Python\Python313\python.exe` | golden model、图像处理、指标绘图 |
| pip | 随 Python | ✅ 25.1.1 | 同上 | 安装 Python 包 |
| Node.js | >= 20 | ✅ v24.19.0 | Codex 运行时内置 | 仅 `web-game/` 原型与本地静态服务器 |
| VS Code | >= 1.90 | ✅ 1.141.0（本次安装，user scope） | `%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe` | 代码编辑、Markdown、Tcl、Python、Git |
| Vivado | **2026.1**（备选 2025.2） | ⚠️ 已安装，**未加入 PATH** | `D:\fpga\2026.1\Vivado\bin\vivado.bat` | 综合、实现、时序、bitstream、xsim 仿真 |
| Vitis / Vitis HLS | 2026.1 | ✅ 已安装 | `D:\fpga\2026.1\Vitis\bin\` | HLS 视觉流水线、PS 侧代码 |
| Model Composer | 2026.1 | ✅ 已安装 | `D:\fpga\2026.1\Model_Composer\` | 备用（Simulink 建模，本项目不强制使用） |
| Icarus Verilog / Verilator | 可选 | ⬜ 未安装 | — | 日常快速语法检查（非必需，xsim 为主） |

> **全员版本必须一致**：工具链差异会导致"我这里能综合、你那里报错"。
> 当前统一为 **Vivado 2026.1**，任何人不得单独升级/降级。

---

## 2. 安装步骤

### 2.1 已就绪项（无需操作）

Git、Python 3.13、Node.js、Vivado/Vitis 2026.1、VS Code（本轮已由 winget 安装）。

### 2.2 Python 图像处理库（**本轮已完成**）

推荐两种方式，**优先虚拟环境**：

**方式 A：项目虚拟环境（推荐，隔离干净）**

```powershell
cd D:\fpga\fpga_space_invaders
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
py -m pip install --upgrade pip
py -m pip install -r requirements.txt
```

> 若 `Activate.ps1` 被执行策略拦截，先执行一次：
> `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

**方式 B：全局安装（快速上手用）**

```powershell
py -m pip install -r requirements.txt
```

安装的包与用途：

| 包 | 用途 |
| --- | --- |
| `numpy` | 数组运算、golden model 数值基础 |
| `opencv-python` | 图像采集/解码、颜色空间、形态学、质心统计 |
| `scipy` | 滤波、连通域、统计 |
| `scikit-image` | 形态学与区域属性对比 |
| `pillow` | 图片读写（BMP/PNG 抓图比对） |
| `matplotlib` | 指标曲线、混淆矩阵、报告插图 |
| `cocotb` | Python 驱动的 RTL 单元测试（需配合仿真器） |

### 2.3 VS Code

已通过 winget 安装（用户级，无需管理员权限）：

```powershell
winget install --id Microsoft.VisualStudioCode --scope user --accept-package-agreements --accept-source-agreements
```

**安装后必须重启终端**（PATH 刷新），随后 `code --version` 应可用。

### 2.4 VS Code 扩展（建议统一安装）

```powershell
code --install-extension mshr-h.veriloghdl          # Verilog / SystemVerilog 高亮与 lint
code --install-extension ms-python.python           # Python
code --install-extension ms-python.vscode-pylance   # Python 语言服务
code --install-extension charliermarsh.ruff         # Python 格式化与 lint
# code --install-extension bitwisecook.tcl          # Tcl 语法：该扩展已从市场下架，装不上
                                                      # Vivado Tcl 脚本按纯文本编辑即可，不影响开发
code --install-extension eamodio.gitlens            # Git 历史
code --install-extension yzhang.markdown-all-in-one # Markdown 写作
code --install-extension marp-team.marp-vscode      # 如需用 Markdown 做 PPT
```

### 2.5 Vivado 环境变量（**重要**）

Vivado 已安装但**不在 PATH**。两种使用方式，团队统一用**方式 A**：

**方式 A：在脚本中显式调用（推荐，可复现）**

```powershell
D:\fpga\2026.1\Vivado\bin\vivado.bat -mode batch -source scripts\create_project.tcl
```

**方式 B：为当前终端临时注入 PATH**

```powershell
D:\fpga\2026.1\Vivado\bin\settings64.bat
# 或在 PowerShell 中：
& "D:\fpga\2026.1\Vivado\bin\settings64.bat"
```

> 不要写死个人绝对路径到仓库脚本里；脚本应支持 `-VivadoRoot` 参数，默认 `D:\fpga\2026.1`。

**本轮实际安装结果（2026-10-11 验证）**

| 扩展 | 状态 |
| --- | --- |
| `mshr-h.veriloghdl` v1.29.0 | ✅ 已安装 |
| `ms-python.python` / `ms-python.debugpy` / `ms-python.vscode-python-envs` | ✅ 已安装（含依赖） |
| `ms-python.vscode-pylance` v2026.4.1 | ✅ 已安装 |
| `charliermarsh.ruff` v2026.86.0 | ✅ 已安装 |
| `eamodio.gitlens` v19.3.0 | ✅ 已安装 |
| `yzhang.markdown-all-in-one` v3.6.3 | ✅ 已安装 |
| `bitwisecook.tcl` | ❌ 扩展已下架，无法安装（不影响开发） |

安装后**必须重启终端**，`code --version` 才会出现在 PATH 中；
若仍不可用，直接用 `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd`。

### 2.6 可选：Icarus Verilog（快速语法检查）

```powershell
# 方式一：Chocolatey（需先安装 choco）
choco install iverilog -y

# 方式二：官方安装包（含 GTKWave）
#   下载 http://bleyer.org/icarus/ 的 x64 安装包后双击安装
```

> 本次**未安装**，若 B/C 觉得每次等 xsim 太慢再补装。使用前需在群里通知。

---

## 3. 关键坑与注意事项

| 坑 | 现象 | 规避方法 |
| --- | --- | --- |
| **`python` 是 Store 占位程序** | 执行 `python xxx.py` 无输出、退出码 1，或弹出应用商店 | **本项目统一用 `py -3`** 或虚拟环境的 `.venv\Scripts\python.exe`，禁止依赖裸 `python` |
| Vivado 不在 PATH | `vivado` 命令找不到 | 用绝对路径调用 `vivado.bat`，或用 `settings64.bat` 注入 |
| PowerShell 脚本中文乱码 | `.ps1` 里的中文导致解析错误（`Unexpected token`） | **所有 `.ps1` 文件必须保存为 UTF-8 with BOM**；`check_env.ps1` 已符合 |
| Python 版本不一致 | 换机器 `opencv` 装不上 | 统一 Python 3.11–3.13；`requirements.txt` 固定最低版本 |
| 虚拟环境被提交进仓库 | `.venv/` 出现在 git status | `.gitignore` 已包含 `.venv/`、`__pycache__/` |
| 中文路径 | Vivado / HLS 在中文路径下报错 | 工程根目录固定为 `D:\fpga\fpga_space_invaders`（纯 ASCII） |
| 空格路径 | Tcl 脚本被空格截断 | 路径不含空格；脚本中用引号包裹路径 |
| 长路径 | Windows 260 字符限制导致综合失败 | 已启用长路径支持；避免过深目录嵌套 |

---

## 4. 环境自检（每次换机 / 每周一次）

```powershell
cd D:\fpga\fpga_space_invaders
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_env.ps1
```

脚本输出 `PASS / WARN / FAIL`：

- `PASS`：就绪；
- `WARN`：可用但有注意事项（如 Vivado 未在 PATH、目标器件未冻结）；
- `FAIL`：必需项缺失，**必须处理后才能开始开发**。

退出码 `0` = 必需项全部通过；`1` = 存在必需项失败。
可覆盖参数：

```powershell
.\scripts\check_env.ps1 -VivadoRoot 'D:\fpga\2026.1' -VsCodeExe 'C:\path\to\Code.exe'
```

**2026-10-11 首次自检结果**

| 检查项 | 状态 | 详情 |
| --- | --- | --- |
| Windows | PASS | Windows 11 家庭版中文版 Build 26200 |
| Git | PASS | 2.56.0.windows.2 |
| Python | PASS | 3.13.5 |
| `python` 命令 | WARN | 指向 Store 占位程序，改用 `py` |
| Python 图像库 | PASS | numpy 2.5.4 / opencv-python 5.0.0 / scipy 1.18.1 / matplotlib 3.11.2 / pillow 12.3.0 / scikit-image 0.26.0 |
| Node.js | PASS | v24.19.0 |
| VS Code | PASS | 1.141.0 |
| Vivado | WARN | 2026.1 已装，未加 PATH |
| Vitis / HLS | PASS | 2026.1 |
| 目标器件 | WARN | 尚未冻结（第 1 周内关闭） |

---

## 5. 各角色额外要求

| 角色 | 必须额外具备 |
| --- | --- |
| A（平台与集成） | Vivado 完整安装（含 Zynq-7000 器件支持）、板卡驱动（Digilent cable / Xilinx cable）、串口终端 |
| B（视觉与 HLS） | Vitis HLS、Python 图像库全部就绪、可访问 `data/gesture/` 数据集 |
| C（游戏与验证） | xsim 可运行、Python golden model 环境、ILA 抓波形能力 |

---

## 6. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
| --- | --- | --- | --- |
| v1.0 | 2026-10-11 | 首次冻结：工具清单、安装步骤、VS Code 扩展、PATH 方案、常见坑、自检流程 | A |