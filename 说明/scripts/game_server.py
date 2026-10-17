#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
手势版太空侵略者服务器（摄像头，无摄像头时自动用鼠标模拟）

用法：
  py scripts/game_server.py
  启动后自动打开浏览器；没自动打开就访问终端打印的地址。

控制来源（自动选择）：
  1. 有摄像头 -> 识别手：手向左挥=左移，向右挥=右移，有手自动射击
  2. 无摄像头 -> 鼠标模拟：左右移动鼠标=左/右，自动射击

游戏操作：START按钮=开始；P=暂停；R=重开
"""
import ctypes
import json
import os
import socket
import sys
import threading
import time
import traceback
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
import numpy as np

# ==================== 可调参数 ====================
SKIN_MIN = np.array([0, 77, 133], dtype=np.uint8)
SKIN_MAX = np.array([255, 127, 173], dtype=np.uint8)
MIN_AREA = 3000
V_THRESH = 8.0        # 摄像头手势：手水平速度阈值
EMA = 0.4             # 速度平滑
MOUSE_V_THRESH = 15.0 # 鼠标模拟：鼠标速度阈值（像素/帧）
AUTO_FIRE = True      # True=自动连射
PORT_START = 8000
# =================================================

WEB_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "web-game"))

gesture_state = {"left": False, "right": False, "fire": False}
lock = threading.Lock()


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


def get_mouse_x():
    pt = POINT()
    ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
    return pt.x


def largest_contour(mask):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    return max(cnts, key=cv2.contourArea) if cnts else None


def get_skin_mask(frame):
    """BGR / RGB 两种颜色空间都试，取皮肤像素更多的一种（自动适配摄像头）。"""
    a = cv2.cvtColor(frame, cv2.COLOR_BGR2YCrCb)
    b = cv2.cvtColor(frame, cv2.COLOR_RGB2YCrCb)
    m1 = cv2.inRange(a, SKIN_MIN, SKIN_MAX)
    m2 = cv2.inRange(b, SKIN_MIN, SKIN_MAX)
    return m1 if cv2.countNonZero(m1) >= cv2.countNonZero(m2) else m2


def update_state(left, right, fire):
    with lock:
        gesture_state["left"] = left
        gesture_state["right"] = right
        gesture_state["fire"] = fire


def camera_loop(cap):
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    prev_cx = None
    vx = 0.0
    frame_no = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame = cv2.flip(frame, 1)
        mask = get_skin_mask(frame)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
        skin = int(cv2.countNonZero(mask))
        cnt = largest_contour(mask)
        cx = None
        if cnt is not None and cv2.contourArea(cnt) >= MIN_AREA:
            M = cv2.moments(cnt)
            cx = int(M["m10"] / M["m00"])
        if cx is None or prev_cx is None:
            vx = 0.0
        else:
            vx = (1.0 - EMA) * vx + EMA * (cx - prev_cx)
        prev_cx = cx
        left = vx < -V_THRESH
        right = vx > V_THRESH
        update_state(left, right, (AUTO_FIRE and cx is not None))
        frame_no += 1
        if frame_no % 30 == 0:
            dirn = "LEFT" if left else ("RIGHT" if right else "STOP")
            print(f"[手势] skin={skin} vx={vx:+.1f} -> {dirn}")


def mouse_loop():
    print("[手势] 没有摄像头 -> 改用鼠标模拟：左右移动鼠标控制战机，自动射击")
    prev_x = None
    vx = 0.0
    frame_no = 0
    while True:
        x = get_mouse_x()
        if prev_x is None:
            vx = 0.0
        else:
            vx = (1.0 - EMA) * vx + EMA * (x - prev_x)
        prev_x = x
        left = vx < -MOUSE_V_THRESH
        right = vx > MOUSE_V_THRESH
        update_state(left, right, AUTO_FIRE)
        frame_no += 1
        if frame_no % 30 == 0:
            dirn = "LEFT" if left else ("RIGHT" if right else "STOP")
            print(f"[鼠标] x={x} vx={vx:+.1f} -> {dirn}")
        time.sleep(0.033)   # ~30fps


def gesture_loop():
    try:
        cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
        if cap.isOpened():
            print("[手势] 摄像头已打开，识别手…")
            camera_loop(cap)
        else:
            mouse_loop()
    except Exception:
        print("[手势] 摄像头线程出错，改用鼠标模拟：")
        traceback.print_exc()
        mouse_loop()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/gesture":
            with lock:
                body = json.dumps(dict(gesture_state)).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        rel = path.lstrip("/") or "index.html"
        file_path = os.path.normpath(os.path.join(WEB_DIR, rel))
        if file_path != WEB_DIR and not file_path.startswith(WEB_DIR + os.sep):
            self.send_error(403)
            return
        if not os.path.isfile(file_path):
            self.send_error(404)
            return
        ext = os.path.splitext(file_path)[1].lower()
        mime = {
            ".html": "text/html; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".mjs": "text/javascript; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".svg": "image/svg+xml",
            ".png": "image/png",
            ".json": "application/json; charset=utf-8",
        }.get(ext, "application/octet-stream")
        with open(file_path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def get_local_ip():
    """取本机在局域网里的 IP（别人用这个地址访问）。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))   # 不发数据，只为拿到默认出口网卡的 IP
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def find_free_port(start):
    for p in range(start, start + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    return None


def main():
    print("启动手势线程…")
    threading.Thread(target=gesture_loop, daemon=True).start()

    port = find_free_port(PORT_START)
    if port is None:
        print("找不到可用端口")
        sys.exit(1)
    try:
        server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    except OSError as e:
        print(f"启动服务器失败: {e}")
        sys.exit(1)

    lan_ip = get_local_ip()
    url = f"http://127.0.0.1:{port}"
    lan_url = f"http://{lan_ip}:{port}"
    print("=" * 56)
    print(f"  本机打开:      {url}")
    print(f"  别人电脑打开:  {lan_url}")
    print("  （别人要和你在同一个 WiFi/局域网）")
    print("  开始=START按钮；暂停=P；重开=R；Ctrl+C 退出")
    print("  别人还进不去 -> 允许 Python 通过 Windows 防火墙")
    print("=" * 56)
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print("\n已退出")


if __name__ == "__main__":
    main()