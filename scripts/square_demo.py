#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
小方块演示程序（左右分屏 + 启动自动标定肤色）

左块：摄像头画面 —— 粗白线勾出手边缘，红色十字标质心
右块：游戏区 —— 黄色小方块，初始中间，只水平移动

启动后先标定：把手放进中间方框按 S，程序自动采样你的肤色；
之后手明显向左/向右挥 -> 方块固定速度左/右；手停/慢 -> 停。

键盘（标定时）：S 采样 | C 用默认肤色 | Q 退出
键盘（运行时）：SPACE 开始/暂停/继续 | R 重开 | C 重新标定 | Q 退出

运行：py scripts/square_demo.py
"""
import sys
import cv2
import numpy as np

# ==================== 可调参数 ====================
DEFAULT_SKIN_MIN = np.array([0, 77, 133], dtype=np.uint8)
DEFAULT_SKIN_MAX = np.array([255, 127, 173], dtype=np.uint8)
MIN_AREA = 3000       # 手部最小面积

V_THRESH = 8.0        # 手水平速度阈值（像素/帧）
EMA = 0.4             # 速度平滑系数

SQUARE_SPEED = 10     # 方块固定速度（像素/帧）
SQUARE_HALF = 20      # 方块半边长
# =================================================


def largest_contour(mask):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    return max(cnts, key=cv2.contourArea) if cnts else None


def calibrate(cap, W, H):
    """启动标定：把手放进中间方框采样肤色。返回 (skin_min, skin_max)。"""
    box = 80
    x0, y0 = W // 2 - box, H // 2 - box
    x1, y1 = W // 2 + box, H // 2 + box
    samples = []
    print("标定：把手（手掌/手背）放进画面中间方框，按 S 采样；按 C 用默认肤色；Q 退出\n")
    while True:
        ok, frame = cap.read()
        if not ok:
            return DEFAULT_SKIN_MIN, DEFAULT_SKIN_MAX
        frame = cv2.flip(frame, 1)
        cv2.rectangle(frame, (x0, y0), (x1, y1), (0, 255, 0), 2)
        cv2.putText(frame, "S=采样  C=默认肤色  Q=退出", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
        cv2.putText(frame, f"已采样 {len(samples)} 帧（把手放进方框）", (10, 60),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        cv2.imshow("demo", frame)
        k = cv2.waitKey(1) & 0xFF
        if k == ord('q'):
            return None
        if k == ord('c'):
            return DEFAULT_SKIN_MIN, DEFAULT_SKIN_MAX
        if k == ord('s'):
            for _ in range(20):   # 采 20 帧
                ok, frame = cap.read()
                if not ok:
                    break
                frame = cv2.flip(frame, 1)
                roi = frame[y0:y1, x0:x1]
                ycrcb = cv2.cvtColor(roi, cv2.COLOR_BGR2YCrCb)
                samples.append((float(ycrcb[..., 1].mean()), float(ycrcb[..., 2].mean())))
                cv2.rectangle(frame, (x0, y0), (x1, y1), (0, 0, 255), 2)
                cv2.putText(frame, "采样中... 手保持不动", (10, 60),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                cv2.imshow("demo", frame)
                cv2.waitKey(1)
            arr = np.array(samples)
            m = 12
            skin_min = np.array([0, max(0, int(arr[:, 0].min() - m)),
                                 max(0, int(arr[:, 1].min() - m))], np.uint8)
            skin_max = np.array([255, min(255, int(arr[:, 0].max() + m)),
                                 min(255, int(arr[:, 1].max() + m))], np.uint8)
            print("标定完成：SKIN_MIN =", skin_min.tolist(), " SKIN_MAX =", skin_max.tolist(), "\n")
            return skin_min, skin_max


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

    # 启动标定
    res = calibrate(cap, W, H)
    if res is None:
        print("退出")
        sys.exit(0)
    SKIN_MIN, SKIN_MAX = res

    square_x = W // 2
    square_y = H // 2
    state = "ready"
    prev_cx = None
    vx = 0.0

    print("SPACE 开始/暂停 | R 重开 | C 重新标定 | Q 退出\n")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame = cv2.flip(frame, 1)

        # 肤色分割
        ycrcb = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
        mask = cv2.inRange(ycrcb, SKIN_MIN, SKIN_MAX)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
        skin = int(cv2.countNonZero(mask))

        cnt = largest_contour(mask)
        cx = cy = None
        if cnt is not None and cv2.contourArea(cnt) >= MIN_AREA:
            M = cv2.moments(cnt)
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])

        # 速度
        if cx is None or prev_cx is None:
            vx = 0.0
        else:
            vx = (1.0 - EMA) * vx + EMA * (cx - prev_cx)
        prev_cx = cx

        # 三状态
        if vx > V_THRESH:
            move = "RIGHT"
        elif vx < -V_THRESH:
            move = "LEFT"
        else:
            move = "STOP"

        # 更新方块
        if state == "running":
            if move == "LEFT":
                square_x -= SQUARE_SPEED
            elif move == "RIGHT":
                square_x += SQUARE_SPEED
        square_x = max(SQUARE_HALF, min(W - SQUARE_HALF, square_x))

        # 左块
        left = frame.copy()
        if cnt is not None and cx is not None:
            cv2.drawContours(left, [cnt], -1, (255, 255, 255), 3)
            cv2.line(left, (cx - 12, cy), (cx + 12, cy), (0, 0, 255), 2)
            cv2.line(left, (cx, cy - 12), (cx, cy + 12), (0, 0, 255), 2)

        # 右块
        right = np.full((H, W, 3), 30, dtype=np.uint8)
        cv2.rectangle(right, (square_x - SQUARE_HALF, square_y - SQUARE_HALF),
                      (square_x + SQUARE_HALF, square_y + SQUARE_HALF), (0, 255, 255), -1)
        cv2.rectangle(right, (square_x - SQUARE_HALF, square_y - SQUARE_HALF),
                      (square_x + SQUARE_HALF, square_y + SQUARE_HALF), (255, 255, 255), 2)
        cv2.putText(right, state.upper(), (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9,
                    (0, 255, 0) if state == "running" else (0, 200, 255), 2, cv2.LINE_AA)
        cv2.putText(right, move, (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.9,
                    (0, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(right, f"vx={vx:+.1f} skin={skin}", (10, 90),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1, cv2.LINE_AA)

        canvas = np.hstack([left, right])
        cv2.line(canvas, (W, 0), (W, H), (120, 120, 120), 2)
        cv2.imshow("demo", canvas)

        key = cv2.waitKey(1) & 0xFF
        if key == 32:
            if state == "ready":
                state = "running"; print("开始")
            elif state == "running":
                state = "paused"; print("暂停")
            else:
                state = "running"; print("继续")
        elif key == ord('r'):
            square_x = W // 2; print("重开：方块回到中间")
        elif key == ord('c'):
            res = calibrate(cap, W, H)
            if res is None:
                break
            SKIN_MIN, SKIN_MAX = res
            prev_cx = None
        elif key == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()
    print("\n已退出")


if __name__ == "__main__":
    main()