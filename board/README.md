# 上板材料与实测证据

> 指南 3.3.5.1 要求：上板工程、运行脚本、实测输出与参考结果的比对数据。

## 本目录内容

| 文件 | 说明 |
|---|---|
| `top_cam_game.xdc` | 光流手势版约束：53 个引脚 + 50/24 MHz 时钟 + 摄像头 CDC `false_path` |
| `top_button_game.xdc` | 按键版约束（无摄像头对照版本） |
| `top_cam_game.bit` | 已验证 bitstream（Vivado 2026.1，`xc7a100tfgg484-2`） |

## 待补充的实测材料（拍好放本目录，文件名用英文）

| # | 材料 | 文件名 | 要点 |
|---|---|---|---|
| 1 | 整机接线 | `photo_setup.jpg` | 板 + 摄像头 + HDMI 显示器全貌 |
| 2 | 待机画面 | `photo_idle.jpg` | S_IDLE 标题画面 |
| 3 | 游戏中 | `photo_play.jpg` | 敌阵 + 炮台 + 4 掩体 + 分数/生命 |
| 4 | **画中画特写** | `photo_pip.jpg` | 挥手时右上角矢量场变红/绿（**最能证明光流在工作**） |
| 5 | 静止对照 | `photo_still.jpg` | 手不动时矢量场全灰 |
| 6 | 掩体破坏 | `photo_bunker.jpg` | 被子弹打出缺口（对应 bunker_bits 逐位写入） |
| 7 | 暂停 | `photo_pause.jpg` | key2 冻结画面 |
| 8 | 通关 | `photo_win.jpg` | 三关全清后 VICTORY 画面 |
| 9 | 失败 | `photo_lose.jpg` | GAME OVER 画面 |
| 10 | 演示视频 | `video_demo.mp4` | 挥手→开始→击敌→掉命→通关 全流程 |

## 上板步骤（复现）

```bash
# 1. 烧写
Vivado → Hardware Manager → Open Target → Program Device → board/top_cam_game.bit
# 2. 环境
摄像头朝向操作者；光照充足；背景有纹理（纯墙光流会失效）
# 3. 操作
挥手左右移动炮台 | key2 开始/暂停/继续 | key3 重开
# 4. 验收
挥手时画中画对应区域红/绿、停手变灰；敌机被击中消失且分数增加
```

## 板级 vs 仿真一致性记录（补数字）

| 检查点 | 仿真参考 | 板级实测 | 一致 |
|---|---|---|---|
| 开局 55 敌机、6 生命 | PASS | | |
| 自动开火 | PASS | | |
| 命中敌机 +10 分 | PASS | | |
| 敌弹命中掉命 + 无敌闪烁 | PASS | | |
| 掩体逐位破坏 | PASS | | |
| UFO 随机出现 | PASS | | |
| 三关递进 | PASS | | |
| 手势左右与镜像对调 | — | | 画面左 = 游戏右 |

## 已知现象与解释

- 综合日志有 `CLOCK_DEDICATED_ROUTE FALSE [get_nets cam1_pclk_IBUF]` 在综合阶段
  求值失败（`Project 1-498`）——正常：该网表在实现阶段才存在，Vivado 会自动移到
  `.Xil/*_propImpl.xdc`，最终约束生效；
- `led_stop/left/right` 被常量 0 驱动（综合警告 `Synth 8-3917`）——设计选择：
  手势状态改由画中画显示，避免 LED 刺眼。