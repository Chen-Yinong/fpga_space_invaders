#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
肤色标定：算出适合你光照/肤色的 YCbCr 阈值。

用法：
  1. 运行后，把手（手掌、手背）放进画面中间的绿色方框里；
  2. 按 s 采样一次（多采几次，换几个角度/位置）；
  3. 按 d 结束，脚本打印出建议的 SKIN_MIN / SKIN_MAX；
  4. 把打印的值填进 gesture_live.py 的"可调参数"里即可。
按键： s 采样 | d 输出结果 | q 退出
"""
import sys
import cv2
import numpy as np

cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
if not cap.isOpened():
    print("摄像头打不开")
    sys.exit(1)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

samples = []
print("把手放进中间绿色方框，按 s 采样（手掌/手背/不同位置各采几次），按 d 输出，q 退出\n")

while True:
    ok, frame = cap.read()
    if not ok:
        break
    frame = cv2.flip(frame, 1)
    h, w = frame.shape[:2]
    x0, y0 = w // 2 - 60, h // 2 - 60
    x1, y1 = w // 2 + 60, h // 2 + 60
    cv2.rectangle(frame, (x0, y0), (x1, y1), (0, 255, 0), 2)

    roi = frame[y0:y1, x0:x1]
    ycrcb = cv2.cvtColor(roi, cv2.COLOR_BGR2YCrCb)
    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
    cb = float(ycrcb[..., 1].mean())
    cr = float(ycrcb[..., 2].mean())
    hh = float(hsv[..., 0].mean())
    ss = float(hsv[..., 1].mean())
    vv = float(hsv[..., 2].mean())

    cv2.putText(frame, f"Cb={cb:.0f} Cr={cr:.0f}   H={hh:.0f} S={ss:.0f} V={vv:.0f}",
                (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
    cv2.putText(frame, f"已采样 {len(samples)} 次  [s]采样 [d]输出 [q]退出",
                (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
    cv2.imshow("skin_calib", frame)

    k = cv2.waitKey(1) & 0xFF
    if k == ord('s'):
        samples.append((cb, cr))
        print(f"采样 #{len(samples)}: Cb={cb:.0f}  Cr={cr:.0f}")
    elif k == ord('d') and len(samples) >= 2:
        arr = np.array(samples)
        cb_min, cb_max = arr[:, 0].min(), arr[:, 0].max()
        cr_min, cr_max = arr[:, 1].min(), arr[:, 1].max()
        m = 12  # 余量
        lo_cb = max(0, int(cb_min - m)); hi_cb = min(255, int(cb_max + m))
        lo_cr = max(0, int(cr_min - m)); hi_cr = min(255, int(cr_max + m))
        print("\n===== 把下面两行填进 gesture_live.py =====")
        print(f"SKIN_MIN = np.array([0, {lo_cb}, {lo_cr}], dtype=np.uint8)")
        print(f"SKIN_MAX = np.array([255, {hi_cb}, {hi_cr}], dtype=np.uint8)")
        print("===========================================\n")
        break
    elif k == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()