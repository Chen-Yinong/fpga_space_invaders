# ppm2png.py — 把仿真导出的 PPM(P6) 转成 PNG（纯标准库，无需第三方包）
# 用法: py sim\ppm2png.py sim\frame.ppm sim\frame.png
import struct, zlib, sys

def read_ppm(path):
    data = open(path, "rb").read()
    idx = 0; fields = []
    while len(fields) < 4:
        while data[idx:idx+1].isspace(): idx += 1
        if data[idx:idx+1] == b"#":
            while data[idx:idx+1] != b"\n": idx += 1
            continue
        s = idx
        while not data[idx:idx+1].isspace(): idx += 1
        fields.append(data[s:idx])
    idx += 1
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[idx:idx+w*h*3]

def write_png(path, w, h, rgb):
    raw = bytearray(); stride = w*3
    for y in range(h):
        raw.append(0)
        raw += rgb[y*stride:(y+1)*stride]
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t+d) & 0xffffffff)
    png  = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)

if __name__ == "__main__":
    w, h, px = read_ppm(sys.argv[1])
    write_png(sys.argv[2], w, h, px)
    print("wrote %s  %dx%d" % (sys.argv[2], w, h))