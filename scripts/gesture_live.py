#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实时动态手势识别（摄像头 + 屏幕大字显示 + 命令行数据）

一次运行，持续识别：手移到不同位置，屏幕上立即显示不同的大字。
  - 手在左区  -> 屏幕大字 "LEFT"   (命令行: 电平=001 向左)
  - 手在右区  -> 屏幕大字 "RIGHT"  (命令行: 电平=010 向右)
  - 手在中区  -> 屏幕大字 "STOP"   (命令行: 电平=000 停止)
  - 张手->握拳 -> 屏幕闪现 "PAUSE!" / "RESUME!"
  - 张手停中区约1秒 -> 屏幕闪现 "START!"

按键：
  q 退出    m 切换显示（原图 / 肤色掩膜 / 叠加标注）

运行：
  py scripts/gesture_live.py
"""
import sys
import time
import cv2
import numpy as np

# ==================== 可调参数 ====================
SKIN_MIN = np.array([0, 119, 101], dtype=np.uint8)   # YCbCr 肤色下限
SKIN_MAX = np.array([255, 144, 125], dtype=np.uint8)  # 上限

MIN_AREA      = 3000    # 手部最小面积
LEFT_ENTER_F  = 0.32    # 质心 x < 0.32*宽 => 进入左区
RIGHT_ENTER_F = 0.68    # 质心 x > 0.68*宽 => 进入右区
LEFT_EXIT_F   = 0.40    # 离开左区（迟滞）
RIGHT_EXIT_F  = 0.60    # 离开右区（迟滞）

FIST_SOLIDITY = 0.82    # 实心度 >= 它 => 握拳
DWELL_FRAMES  = 30      # 张手停中区多少帧 = 开始
EDGE_COOLDOWN = 15      # 事件冷却帧数
FLASH_SEC     = 1.2     # 屏幕事件大字停留秒数
# =================================================

LEVEL_NONE, LEVEL_LEFT, LEVEL_RIGHT = "000", "001", "010"


def largest_contour(mask):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    return max(cnts, key=cv2.contourArea) if cnts else None


def draw_hud(frame, level_name, paused, open_hand, flash, flash_until, cx, cy):
    """在画面上叠加大字 HUD。"""
    h, w = frame.shape[:2]
    band = frame.copy()
    cv2.rectangle(band, (0, 0), (w, 92), (0, 0, 0), -1)
    frame = cv2.addWeighted(band, 0.45, frame, 0.55, 0)

    color = (0, 255, 0) if level_name != "STOP" else (210, 210, 210)
    cv2.putText(frame, level_name, (18, 62), cv2.FONT_HERSHEY_SIMPLEX,
                1.8, color, 4, cv2.LINE_AA)

    status = "PAUSED" if paused else "RUNNING"
    hand = "FIST" if not open_hand else "OPEN"
    scolor = (0, 0, 255) if paused else (0, 255, 0)
    cv2.putText(frame, f"{status}   HAND:{hand}", (20, 88),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, scolor, 2, cv2.LINE_AA)

    cv2.circle(frame, (cx, cy), 9, (0, 0, 255), 2)
    if flash and time.time() < flash_until:
        (tw, th), _ = cv2.getTextSize(flash, cv2.FONT_HERSHEY_SIMPLEX, 2.2, 6)
        cv2.putText(frame, flash, ((w - tw) // 2, h // 2), cv2.FONT_HERSHEY_SIMPLEX,
                    2.2, (0, 255, 255), 6, cv2.LINE_AA)
    return frame


def main():
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print("打不开摄像头：检查是否被占用 / 是否有摄像头")
        sys.exit(1)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    ok, frame = cap.read()
    if not ok:
        print("读不到画面")
        sys.exit(1)
    H, W = frame.shape[:2]
    left_enter  = LEFT_ENTER_F * W
    right_enter = RIGHT_ENTER_F * W
    left_exit   = LEFT_EXIT_F * W
    right_exit  = RIGHT_EXIT_F * W

    state = "idle"
    prev_open = False
    dwell_cnt = 0
    cooldown = 0
    paused = False
    view = 0
    flash, flash_until = "", 0.0

    print(f"画面 {W}x{H}，动态识别中。手移到不同位置，屏幕大字会变。q 退出 / m 切换显示\n")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame = cv2.flip(frame, 1)

        # 1) 肤色分割
        ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
        mask = cv2.inRange(ycrcb, SKIN_MIN, SKIN_MAX)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
        skin_pixels = int(cv2.countNonZero(mask))

        cnt = largest_contour(mask)
        if cnt is None or cv2.contourArea(cnt) < MIN_AREA:
            sys.stdout.write(f"\r无手（skin={skin_pixels} 手没进画面或肤色阈值不对）      ")
            sys.stdout.flush()
            state, prev_open, dwell_cnt = "idle", False, 0
            show = cv2.cvtColor(mask, cv2.COLOR_GRAY2BGR) if view == 1 else frame
            show = draw_hud(show, "STOP", paused, True, "", 0, W // 2, 40)
            cv2.imshow("gesture", show)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            if key == ord('m'):
                view = (view + 1) % 3
            continue

        # 2) 特征
        area = cv2.contourArea(cnt)
        M = cv2.moments(cnt)
        cx = int(M["m10"] / M["m00"])
        cy = int(M["m01"] / M["m00"])
        hull = cv2.convexHull(cnt)
        hull_area = cv2.contourArea(hull)
        solidity = area / hull_area if hull_area else 0
        open_hand = solidity < FIST_SOLIDITY

        pts = cnt.reshape(-1, 2)
        d2 = (pts[:, 0] - cx) ** 2 + (pts[:, 1] - cy) ** 2
        tip = pts[int(d2.argmax())]
        dx = int(tip[0] - cx)

        # 3) 位置 -> 电平命令（迟滞）
        if state in ("idle", "left") and cx < left_enter:
            state = "left"
        elif state in ("idle", "right") and cx > right_enter:
            state = "right"
        elif state == "left" and cx > left_exit:
            state = "idle"
        elif state == "right" and cx < right_exit:
            state = "idle"
        level = {"left": LEVEL_LEFT, "right": LEVEL_RIGHT}.get(state, LEVEL_NONE)
        level_cn = {"001": "向左", "010": "向右"}.get(level, "停止")
        level_en = {"001": "LEFT", "010": "RIGHT"}.get(level, "STOP")

        # 4) 事件
        event = ""
        if cooldown > 0:
            cooldown -= 1
        if (not open_hand) and prev_open and cooldown == 0:
            paused = not paused
            event = "PAUSE!" if paused else "RESUME!"
            cooldown = EDGE_COOLDOWN
        prev_open = open_hand

        if open_hand and state == "idle":
            dwell_cnt += 1
        else:
            dwell_cnt = 0
        if dwell_cnt == DWELL_FRAMES and cooldown == 0:
            event = "START!"
            cooldown = EDGE_COOLDOWN
            dwell_cnt = 0
        if event:
            flash, flash_until = event, time.time() + FLASH_SEC
            print(f"\n>>> 事件: {event}")

        # 5) 命令行数据（单行刷新）
        sys.stdout.write(
            f"\rskin={skin_pixels} cx={cx:3d} 面积={int(area):5d} 实心度={solidity:.2f} 拇指dx={dx:+3d} | "
            f"电平={level}({level_cn}) | {'张手' if open_hand else '握拳'} | "
            f"{'暂停中' if paused else '运行中'}  ")
        sys.stdout.flush()

        # 6) 显示
        if view == 1:
            show = cv2.cvtColor(mask, cv2.COLOR_GRAY2BGR)
        elif view == 2:
            show = frame.copy()
            cv2.drawContours(show, [cnt], -1, (0, 255, 0), 2)
            cv2.circle(show, tuple(map(int, tip)), 6, (255, 0, 0), -1)
        else:
            show = frame.copy()
        show = draw_hud(show, level_en, paused, open_hand, flash, flash_until, cx, cy)
        cv2.imshow("gesture", show)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        if key == ord('m'):
            view = (view + 1) % 3

    cap.release()
    cv2.destroyAllWindows()
    print("\n已退出")


if __name__ == "__main__":
    main()