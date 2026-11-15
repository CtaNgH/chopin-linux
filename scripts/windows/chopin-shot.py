#!/usr/bin/env python3
"""chopin-shot.py - grab the X root window and write a downscaled PNG.

No screenshot tools (xwd, imagemagick) on the chopin rootfs, but python3 and
libX11 are there.  XGetImage() gives us the raw framebuffer; we resample it
nearest-neighbour and emit a plain RGB PNG with zlib.  Usage:

    DISPLAY=:0 XAUTHORITY=... python3 chopin-shot.py /tmp/shot.png [scale]
"""
import ctypes, struct, sys, zlib

W = ctypes


class XImage(ctypes.Structure):
    _fields_ = [
        ("width", W.c_int), ("height", W.c_int),
        ("xoffset", W.c_int), ("format", W.c_int),
        ("data", W.c_void_p),
        ("byte_order", W.c_int), ("bitmap_unit", W.c_int),
        ("bitmap_bit_order", W.c_int), ("bitmap_pad", W.c_int),
        ("depth", W.c_int), ("bytes_per_line", W.c_int),
        ("bits_per_pixel", W.c_int),
        ("red_mask", W.c_ulong), ("green_mask", W.c_ulong), ("blue_mask", W.c_ulong),
        ("obdata", W.c_void_p),
        ("f", W.c_void_p * 8),
    ]


def png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(out)
    return len(out)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/shot.png"
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 2

    x11 = ctypes.CDLL("libX11.so.6")
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XDefaultScreen.restype = ctypes.c_int
    x11.XDisplayWidth.restype = ctypes.c_int
    x11.XDisplayHeight.restype = ctypes.c_int
    x11.XRootWindow.restype = ctypes.c_ulong
    x11.XRootWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XGetImage.restype = ctypes.POINTER(XImage)
    x11.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                              ctypes.c_ulong, ctypes.c_int]
    x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]

    dpy = x11.XOpenDisplay(None)
    if not dpy:
        sys.exit("cannot open display")
    scr = x11.XDefaultScreen(dpy)
    root = x11.XRootWindow(dpy, scr)
    dw, dh = x11.XDisplayWidth(dpy, scr), x11.XDisplayHeight(dpy, scr)
    img = x11.XGetImage(dpy, root, 0, 0, dw, dh, ~0, 2)  # ZPixmap
    if not img:
        sys.exit("XGetImage failed")
    im = img.contents
    if im.bits_per_pixel != 32:
        sys.exit("unexpected depth: bpp=%d" % im.bits_per_pixel)

    buf = ctypes.string_at(im.data, im.bytes_per_line * im.height)
    bpl = im.bytes_per_line
    ow, oh = dw // scale, dh // scale
    rows = []
    for y in range(oh):
        sy = y * scale
        line = buf[sy * bpl: sy * bpl + dw * 4]
        row = bytearray()
        for x in range(ow):
            i = x * scale * 4
            row += bytes((line[i + 2], line[i + 1], line[i]))  # BGRA -> RGB
        rows.append(row)
    size = png(path, ow, oh, rows)
    print("%s %dx%d -> %dx%d %d bytes" % (path, dw, dh, ow, oh, size))


if __name__ == "__main__":
    main()
