#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
握拳手势方向 golden model（纯标准库，零第三方依赖，方便任何人直接跑）

算法（与后续 RTL 一一对应）：
  二值手部掩膜
    -> 3x3 开运算去噪
    -> Chamfer 3-4 距离变换（两遍扫描，和 RTL 行缓冲实现一致）
    -> 掌心 P = DT 最大值位置（多个点取质心）
    -> 拇指尖 T = 掩膜内离 P 最远的点（只比较平方距离，无开方无除法）
    -> dx = T.x - P.x  ->  left / right / none

运行：  python scripts/gesture_golden_model.py
"""
import random

W, H = 320, 240
INF = 1 << 20


def make_fist_mask(direction):
    """合成「握拳 + 拇指指向」掩膜，验证算法。direction: 'left' / 'right' / 'none'"""
    m = [[0] * W for _ in range(H)]
    cy, cx = 140, 160

    def fill(y0, y1, x0, x1):
        for y in range(max(0, y0), min(H, y1)):
            for x in range(max(0, x0), min(W, x1)):
                m[y][x] = 1

    # 拳：椭圆
    for y in range(H):
        for x in range(W):
            if ((x - cx) ** 2) / 38 ** 2 + ((y - cy) ** 2) / 32 ** 2 <= 1.0:
                m[y][x] = 1
    # 手腕：向下
    fill(cy + 20, cy + 70, cx - 22, cx + 22)
    # 拇指：向一侧伸出
    if direction == "left":
        fill(cy - 16, cy + 20, 55, cx - 30)
        fill(cy - 10, cy + 14, 42, 55)
    elif direction == "right":
        fill(cy - 16, cy + 20, cx + 30, 265)
        fill(cy - 10, cy + 14, 265, 278)
    # 少量椒盐噪声
    r = random.Random(0)
    for _ in range(80):
        m[r.randrange(H)][r.randrange(W)] = 1
    return m


def opening(m):
    """3x3 形态学开运算（先腐蚀后膨胀），去掉孤立噪声。"""
    e = [[0] * W for _ in range(H)]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if all(m[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                e[y][x] = 1
    d = [[0] * W for _ in range(H)]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if any(e[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                d[y][x] = 1
    return d


def chamfer_dt(m):
    """Chamfer 3-4 距离变换，两遍扫描（背景距离 0，前景向邻居 +3/+4 传播）。"""
    dt = [[0 if m[y][x] == 0 else INF for x in range(W)] for y in range(H)]
    for y in range(H):
        for x in range(W):
            if m[y][x] == 0:
                continue
            v = INF
            if x > 0 and dt[y][x - 1] + 3 < v:
                v = dt[y][x - 1] + 3
            if y > 0 and dt[y - 1][x] + 3 < v:
                v = dt[y - 1][x] + 3
            if x > 0 and y > 0 and dt[y - 1][x - 1] + 4 < v:
                v = dt[y - 1][x - 1] + 4
            dt[y][x] = v
    for y in range(H - 1, -1, -1):
        for x in range(W - 1, -1, -1):
            if m[y][x] == 0:
                continue
            v = dt[y][x]
            if x < W - 1 and dt[y][x + 1] + 3 < v:
                v = dt[y][x + 1] + 3
            if y < H - 1 and dt[y + 1][x] + 3 < v:
                v = dt[y + 1][x] + 3
            if x < W - 1 and y < H - 1 and dt[y + 1][x + 1] + 4 < v:
                v = dt[y + 1][x + 1] + 4
            dt[y][x] = v
    return dt


def classify(mask, enter_th=25, min_dist=50):
    m = opening(mask)
    area = sum(sum(r) for r in m)
    if area < 500:
        return dict(direction="none", reason="hand too small", area=area)

    dt = chamfer_dt(m)

    # 掌心 = DT 最大值位置（多个点取质心）
    best = -1
    pts = []
    for y in range(H):
        for x in range(W):
            if m[y][x] and dt[y][x] > best:
                best = dt[y][x]
                pts = [(x, y)]
            elif m[y][x] and dt[y][x] == best:
                pts.append((x, y))
    px = sum(p[0] for p in pts) // len(pts)
    py = sum(p[1] for p in pts) // len(pts)

    # 拇指尖 = 离掌心最远的前景点
    bd = -1
    tx = ty = 0
    for y in range(H):
        for x in range(W):
            if m[y][x]:
                d2 = (x - px) ** 2 + (y - py) ** 2
                if d2 > bd:
                    bd = d2
                    tx, ty = x, y
    dist = int(bd ** 0.5)
    dx = tx - px

    if dist < min_dist:
        return dict(palm=(px, py), tip=(tx, ty), dx=dx, dist=dist, direction="none", reason="thumb not extended", area=area)
    if dx > enter_th:
        d = "right"
    elif dx < -enter_th:
        d = "left"
    else:
        d = "none"
    return dict(palm=(px, py), tip=(tx, ty), dx=dx, dist=dist, direction=d, reason="ok", area=area)


def main():
    print(f"{'手势':8s} {'判定':8s} {'dx':>6s}  {'dist':>5s}  palm         tip")
    for d in ["left", "right", "none"]:
        r = classify(make_fist_mask(d))
        print(f"{d:8s} {r['direction']:8s} {r.get('dx', '-'):>6}  {r.get('dist', '-'):>5}  {r.get('palm')}  {r.get('tip')}")

    l = classify(make_fist_mask("left"))["direction"] == "left"
    rr = classify(make_fist_mask("right"))["direction"] == "right"
    n = classify(make_fist_mask("none"))["direction"] == "none"
    print("\n[结论] left=%s right=%s none=%s  =>  %s" % (l, rr, n, "PASS" if (l and rr and n) else "FAIL"))


if __name__ == "__main__":
    main()