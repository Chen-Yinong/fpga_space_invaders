# fpga_space_invaders

> 基于 **AMD 7 Series FPGA** 的**低延迟无接触手势交互平台**，以「太空侵略者」游戏作为演示载体。
> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 自主选题（3.3）

**一句话定位**：摄像头采集 → PL 视觉流水线 → 手势命令 → 游戏核心 → 并行碰撞判定 → 实时显示，
全链路在 FPGA 上以硬件流水线完成，不依赖 PS 侧 OpenCV。

---

## 1. 系统链路

```
摄像头 640x480@30fps (DVP + SCCB)
        |
        v
PL 视频采集与同步 -> 灰度化 / 降采样 -> 帧差 / 肤色分割
        -> 形态学滤波 -> 手部区域统计 -> 质心 / 面积 / 张开度
        -> 手势状态机（左移 / 右移 / 射击 / 开始）  [doc: gesture_spec.md]
        -> 游戏核心（玩家 / 子弹 / 敌机 / 并行碰撞 / 计分）
        -> 精灵与字符生成 -> VGA 640x480@60 显示
```

- 视觉处理分辨率：320×240（2×2 降采样）
- 游戏内部坐标：320×240，显示上采样到 640×480
- 主时钟：`clk_sys = 100 MHz`；像素时钟：`clk_pix = 25.2 MHz`
- 片内总线：AXI4-Stream（视频）+ AXI4-Lite（寄存器）

详见 [`docs/interface_spec.md`](docs/interface_spec.md)。

---

## 2. 四种手势

| 编号 | 手势 | 游戏动作 | 判别方式 |
| --- | --- | --- | --- |
| G1 | 左移 | 战机向左 | 质心进入左区（≤192）+ 手掌张开，迟滞退出（≥256） |
| G2 | 右移 | 战机向右 | 质心进入右区（≥448）+ 手掌张开，迟滞退出（≤384） |
| G3 | 射击 | 发射子弹 | 张开度由高到低的下降沿，冷却 300 ms |
| G4 | 开始 / 重开 | 开新一局 | 1.5 s 内往复挥手 ≥ 4 次符号变化 |

详见 [`docs/gesture_spec.md`](docs/gesture_spec.md)。

---

## 3. 快速上手

```powershell
git clone https://github.com/Chen-Yinong/fpga_space_invaders.git
cd fpga_space_invaders

# 1) 环境自检（必需）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_env.ps1

# 2) 安装 Python 依赖（若自检提示缺少）
py -m pip install -r requirements.txt

# 3) 重建 Vivado 工程（工程必须由脚本生成，禁止手工 GUI 建工程）
D:\fpga\2026.1\Vivado\bin\vivado.bat -mode batch -source scripts\create_project.tcl
```

> **注意**：本项目统一使用 `py -3`，不要用裸 `python`（本机上是 Microsoft Store 占位程序）。

阅读顺序：`README.md` → `docs/interface_spec.md` → `docs/gesture_spec.md` → `docs/repo_conventions.md`。

---

## 4. 目录结构

| 目录 | 内容 |
| --- | --- |
| `docs/` | 设计文档：架构、手势、接口、规范、环境、测试、AI 日志 |
| `src/rtl/` | 手写 RTL（Verilog / SystemVerilog） |
| `src/hls/` | Vitis HLS 视觉流水线源码 |
| `src/ps/` | PS 侧代码（仅配置、日志，不承担视觉计算） |
| `sim/` | Testbench、cocotb 用例、测试向量 |
| `constraints/` | XDC 约束文件 |
| `build/` | Vivado 工程与构建产物（**不入库**） |
| `scripts/` | 自动化脚本（环境自检、工程重建、指标提取） |
| `board/` | 上板照片、接线图、验证记录 |
| `data/` | 小型测试数据；手势数据集见 `data/README.md` |
| `metrics/` | 延迟 / 帧率 / 资源指标与证据 |
| `skill/` | 可复用 Skill 与提示词模板 |
| `report/` | 设计报告、PPT、演示视频 |
| `web-game/` | 浏览器原型（算法验证与演示对比，**非最终交付物**） |

---

## 5. 团队分工

| 角色 | 职责 | 工作包 |
| --- | --- | --- |
| **A** 平台与集成 | 板卡、摄像头、显示、AXI、时钟约束、每周集成、仓库与构建 | WP0 + WP1 |
| **B** 视觉与 HLS | 图像预处理、手势识别、HLS IP、准确率与延迟测试 | WP2 |
| **C** 游戏显示与验证 | 游戏 FSM、并行碰撞、精灵显示、Testbench、golden model 对比、指标统计 | WP3 + WP4 |
| 全员 | AI 协作记录、Skill 提炼、文档与报告 | WP6 |

---

## 6. 文档索引

| 文档 | 说明 |
| --- | --- |
| [`docs/gesture_spec.md`](docs/gesture_spec.md) | **四种手势定义（唯一权威）** |
| [`docs/interface_spec.md`](docs/interface_spec.md) | **时钟 / 接口 / 寄存器 / 坐标标准（唯一权威）** |
| [`docs/repo_conventions.md`](docs/repo_conventions.md) | 仓库使用规范 |
| [`docs/environment_setup.md`](docs/environment_setup.md) | 环境与软件安装 |
| [`docs/phase0_checklist.md`](docs/phase0_checklist.md) | 第零阶段交付清单 |
| [`docs/ai_collaboration.md`](docs/ai_collaboration.md) | AI 协作日志 |
| [`docs/architecture.md`](docs/architecture.md) | 系统架构与数据流 |

---

## 7. 关键约束（红线）

1. **摄像头必须由 PL 直接采集**，禁止「PS 跑 OpenCV 再把结果喂给 FPGA」。
2. **禁止手工 GUI 建 Vivado 工程**，必须用 Tcl 脚本可复现重建。
3. **冻结文档先改后写代码**：改阈值必须先改 `gesture_spec.md`。
4. **目录与文件名只用英文小写 + 数字 + `_` + `-`**，中文只出现在内容里。
5. **大文件不入库**（`.bit`、`.dcp`、原始视频、波形文件）。
6. **每天 22:00 前提交代码**，`dev` 分支必须保持可构建。

---

## 8. 许可

见 [`LICENSE`](LICENSE)（MIT 或 Apache-2.0）。