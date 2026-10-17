#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
手控小方块演示程序
==================

画面左右两块：
  左块：摄像头实时画面。用粗白线勾出手的边缘，用红色十字标出质心。
  右块：一个小方块，只在水平方向移动（无 y 方向位移），初始位于右块中央。

操作全部用键盘：
  空格 Space     开始 / 暂停
  R / r          重开（小方块回到中间，并重新开始）
  C / c          现采肤色（把手放进画面中央采样框后按 C）
  Q / q / Esc    退出

手部状态的判断：
  根据质心的水平速度判断，只区分三种状态——
    STOP  质心基本不动或移动很慢（|速度| < 阈值）
    LEFT  明显向左移动
    RIGHT 明显向右移动
  小方块在 LEFT / RIGHT 状态下分别以固定速度向左 / 向右移动。

依赖：
  pip install opencv-python numpy
"""

import time

try:
    import cv2
    import numpy as np
except ImportError as exc:  # 缺少依赖时给出友好提示
    print("缺少运行依赖：", exc)
    print("请先安装依赖，例如执行：pip install opencv-python numpy")
    try:
        input("按回车键退出...")
    except EOFError:
        pass
    raise SystemExit(1)


# ------------------------- 可调参数 -------------------------
CAMERA_INDEX = 0            # 摄像头编号，通常内置摄像头为 0
FRAME_W = 640               # 单块画面宽度（左块 = 摄像头宽度）
FRAME_H = 480               # 画面高度

MIN_HAND_AREA = 1800        # 小于该面积的手部轮廓会被忽略（过滤噪声）
HAND_VX_THRESHOLD = 110.0   # 质心水平速度阈值（像素/秒），超过才算“明显”移动
VX_EMA_ALPHA = 0.12         # 速度平滑系数，越大越灵敏、越抖

SQUARE_SIZE = 46            # 小方块边长（像素）
SQUARE_SPEED = 280.0        # 小方块固定移动速度（像素/秒）
SQUARE_MARGIN = 8           # 小方块与右块边界的间距

CONTOUR_THICKNESS = 4       # 手部边缘粗白线的粗细
CROSS_HALF = 14             # 红色十字半长
CROSS_THICKNESS = 3         # 红色十字粗细


def build_skin_mask(bgr: np.ndarray, ranges=None) -> np.ndarray:
    """用 HSV + YCrCb 两种肤色范围取交集，得到手部候选区域。

    ranges 为 None 时使用内置默认范围；否则使用现采的肤色范围。
    ranges 的格式：((lower_hsv, upper_hsv), (lower_ycrcb, upper_ycrcb))。
    """
    blurred = cv2.GaussianBlur(bgr, (5, 5), 0)

    hsv = cv2.cvtColor(blurred, cv2.COLOR_BGR2HSV)
    ycrcb = cv2.cvtColor(blurred, cv2.COLOR_BGR2YCrCb)

    if ranges is None:
        lower_hsv = np.array([0, 20, 60], dtype=np.uint8)
        upper_hsv = np.array([25, 255, 255], dtype=np.uint8)
        lower_ycrcb = np.array([0, 133, 77], dtype=np.uint8)
        upper_ycrcb = np.array([255, 173, 127], dtype=np.uint8)
    else:
        (lower_hsv, upper_hsv), (lower_ycrcb, upper_ycrcb) = ranges

    mask_hsv = cv2.inRange(hsv, lower_hsv, upper_hsv)
    mask_ycrcb = cv2.inRange(ycrcb, lower_ycrcb, upper_ycrcb)

    mask = cv2.bitwise_and(mask_hsv, mask_ycrcb)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    return mask


def sample_skin_ranges(bgr: np.ndarray):
    """现采肤色：取画面中央采样框内的像素，按均值 ± k 倍标准差生成范围。"""
    h, w = bgr.shape[:2]
    box_w = int(w * 0.40)
    box_h = int(h * 0.40)
    x0 = (w - box_w) // 2
    y0 = (h - box_h) // 2
    roi = bgr[y0:y0 + box_h, x0:x0 + box_w]

    def _mean_std_ranges(img, k=2.5):
        mean = img.mean(axis=(0, 1))
        std = img.std(axis=(0, 1))
        lower = np.clip(mean - k * std, 0, 255).astype(np.uint8)
        upper = np.clip(mean + k * std, 0, 255).astype(np.uint8)
        return lower, upper

    hsv_ranges = _mean_std_ranges(cv2.cvtColor(roi, cv2.COLOR_BGR2HSV))
    ycrcb_ranges = _mean_std_ranges(cv2.cvtColor(roi, cv2.COLOR_BGR2YCrCb))
    return hsv_ranges, ycrcb_ranges


def draw_calibration_box(frame: np.ndarray, calibrated: bool) -> None:
    """在左块画采样框和提示文字。"""
    h, w = frame.shape[:2]
    box_w = int(w * 0.40)
    box_h = int(h * 0.40)
    x0 = (w - box_w) // 2
    y0 = (h - box_h) // 2
    cv2.rectangle(frame, (x0, y0), (x0 + box_w, y0 + box_h),
                  (0, 255, 255), 2)
    cv2.line(frame, (x0, y0 + box_h // 2), (x0 + box_w, y0 + box_h // 2),
             (0, 255, 255), 1)
    cv2.line(frame, (x0 + box_w // 2, y0), (x0 + box_w // 2, y0 + box_h),
             (0, 255, 255), 1)

    if calibrated:
        text = "Skin sampled - C to resample"
    else:
        text = "Put hand in box, press C to sample"
    cv2.putText(frame, text, (12, 36),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2, cv2.LINE_AA)


def find_largest_hand_contour(mask: np.ndarray):
    """返回面积最大的手部轮廓；没有足够大的轮廓时返回 None。"""
    contours, _ = cv2.findContours(
        mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    if not contours:
        return None

    largest = max(contours, key=cv2.contourArea)
    if cv2.contourArea(largest) < MIN_HAND_AREA:
        return None
    return largest


def draw_hand_overlay(frame: np.ndarray, contour) -> None:
    """在原图上画粗白轮廓和红色质心十字。"""
    cv2.drawContours(frame, [contour], -1, (255, 255, 255), CONTOUR_THICKNESS)

    moments = cv2.moments(contour)
    if moments["m00"] <= 0:
        return
    cx = int(moments["m10"] / moments["m00"])
    cy = int(moments["m01"] / moments["m00"])

    cv2.line(frame, (cx - CROSS_HALF, cy), (cx + CROSS_HALF, cy),
             (0, 0, 255), CROSS_THICKNESS)
    cv2.line(frame, (cx, cy - CROSS_HALF), (cx, cy + CROSS_HALF),
             (0, 0, 255), CROSS_THICKNESS)
    cv2.circle(frame, (cx, cy), 3, (0, 0, 255), -1)


def centroid_x(contour):
    """返回轮廓质心的 x 坐标；无法计算时返回 None。"""
    moments = cv2.moments(contour)
    if moments["m00"] <= 0:
        return None
    return moments["m10"] / moments["m00"]


def draw_right_panel(square_center_x: int, square_y: int,
                     hand_state: str, running: bool) -> np.ndarray:
    """绘制右块：深色背景 + 小方块 + 状态文字。"""
    panel = np.full((FRAME_H, FRAME_W, 3), (34, 34, 34), dtype=np.uint8)

    # 小方块（绿色）
    left = square_center_x - SQUARE_SIZE // 2
    top = square_y
    cv2.rectangle(panel, (left, top),
                  (left + SQUARE_SIZE, top + SQUARE_SIZE),
                  (0, 255, 0), -1)
    cv2.rectangle(panel, (left, top),
                  (left + SQUARE_SIZE, top + SQUARE_SIZE),
                  (255, 255, 255), 2)

    # 状态文字
    color = (0, 165, 255)
    if hand_state == "LEFT":
        color = (0, 200, 255)
    elif hand_state == "RIGHT":
        color = (0, 200, 255)

    status = "RUNNING" if running else "PAUSED"
    cv2.putText(panel, f"Hand: {hand_state}", (12, 36),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2, cv2.LINE_AA)
    cv2.putText(panel, status, (12, 68),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.putText(panel, "Space: start/pause", (12, FRAME_H - 74),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (180, 180, 180), 1, cv2.LINE_AA)
    cv2.putText(panel, "R: restart   Q: quit", (12, FRAME_H - 44),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (180, 180, 180), 1, cv2.LINE_AA)
    return panel


def main() -> None:
    print("正在打开摄像头...")
    cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        print("无法打开摄像头，请确认摄像头可用且未被其他程序占用。")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_H)

    cv2.namedWindow("Hand Control Demo", cv2.WINDOW_NORMAL)

    running = False
    hand_state = "STOP"
    skin_ranges = None  # 为 None 时用默认肤色范围，按 C 现采后使用实测范围

    # 小方块初始位于右块中央（此坐标为右块内部坐标，范围 0 ~ FRAME_W）
    square_center_x = FRAME_W // 2
    square_y = FRAME_H // 2 - SQUARE_SIZE // 2

    # 质心速度跟踪状态
    prev_cx = None
    last_frame_time = None
    smoothed_vx = 0.0

    print("操作说明：")
    print("  空格  开始 / 暂停")
    print("  R     重开（小方块回到中间）")
    print("  C     现采肤色（把手放进画面中央采样框后按 C）")
    print("  Q/Esc 退出")

    while True:
        ok, frame = cap.read()
        if not ok:
            print("读取摄像头画面失败。")
            break

        # 水平翻转，像照镜子一样：手向左移，画面里的手也向左移
        frame = cv2.flip(frame, 1)
        frame = cv2.resize(frame, (FRAME_W, FRAME_H))

        now = time.monotonic()
        frame_dt = 0.0
        if last_frame_time is not None:
            # 限制单帧时间，避免卡顿造成速度突跳
            frame_dt = min(now - last_frame_time, 0.1)

        mask = build_skin_mask(frame, skin_ranges)
        contour = find_largest_hand_contour(mask)

        if contour is not None:
            draw_hand_overlay(frame, contour)
            cx = centroid_x(contour)

            if prev_cx is None:
                smoothed_vx = 0.0
            elif frame_dt > 0:
                vx = (cx - prev_cx) / frame_dt
                smoothed_vx = (1.0 - VX_EMA_ALPHA) * smoothed_vx + VX_EMA_ALPHA * vx

            prev_cx = cx

            if smoothed_vx > HAND_VX_THRESHOLD:
                hand_state = "RIGHT"
            elif smoothed_vx < -HAND_VX_THRESHOLD:
                hand_state = "LEFT"
            else:
                hand_state = "STOP"
        else:
            # 没检测到手：方块不动，并重置速度跟踪
            hand_state = "STOP"
            prev_cx = None
            smoothed_vx = 0.0
            cv2.putText(frame, "No hand detected", (12, 68),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2, cv2.LINE_AA)

        draw_calibration_box(frame, skin_ranges is not None)

        # 根据手部状态移动小方块（暂停时不动）
        if running:
            if hand_state == "LEFT":
                square_center_x -= SQUARE_SPEED * frame_dt
            elif hand_state == "RIGHT":
                square_center_x += SQUARE_SPEED * frame_dt

            min_x = SQUARE_MARGIN + SQUARE_SIZE // 2
            max_x = FRAME_W - SQUARE_MARGIN - SQUARE_SIZE // 2
            square_center_x = int(max(min_x, min(max_x, square_center_x)))

        right_panel = draw_right_panel(int(square_center_x), square_y,
                                       hand_state, running)
        display = np.hstack((frame, right_panel))

        # 左右分块之间的分隔线
        cv2.line(display, (FRAME_W - 1, 0), (FRAME_W - 1, FRAME_H - 1),
                 (90, 90, 90), 2)

        cv2.imshow("Hand Control Demo", display)
        key = cv2.waitKey(1) & 0xFF

        if key in (ord("q"), ord("Q"), 27):
            break
        elif key == ord(" "):
            running = not running
        elif key in (ord("r"), ord("R")):
            square_center_x = FRAME_W // 2
            prev_cx = None
            last_frame_time = None
            smoothed_vx = 0.0
            hand_state = "STOP"
            running = True
        elif key in (ord("c"), ord("C")):
            skin_ranges = sample_skin_ranges(frame)
            print("已现采肤色，按 C 可随时重新采集。")

        last_frame_time = now

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
