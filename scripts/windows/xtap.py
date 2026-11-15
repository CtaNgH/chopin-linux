#!/usr/bin/env python3
'''xtap.py - show a white square on Xwayland and log where clicks land.

The point: a tap on the centre of a known window gives us ground truth in
*logical* screen coordinates, so we can tell whether the reported touch
position (evtest) and the compositor mapping agree.
'''
import ctypes, sys, time

W = ctypes
x11 = W.CDLL("libX11.so.6")


class ButtonEvent(W.Structure):
    _fields_ = [("type", W.c_int), ("serial", W.c_ulong), ("send_event", W.c_int),
                ("display", W.c_void_p), ("window", W.c_ulong), ("root", W.c_ulong),
                ("subwindow", W.c_ulong), ("time", W.c_ulong),
                ("x", W.c_int), ("y", W.c_int),
                ("x_root", W.c_int), ("y_root", W.c_int),
                ("state", W.c_uint), ("button", W.c_uint), ("same_screen", W.c_int)]


def main():
    x11.XOpenDisplay.restype = W.c_void_p
    x11.XOpenDisplay.argtypes = [W.c_char_p]
    x11.XDefaultScreen.restype = W.c_int
    x11.XRootWindow.restype = W.c_ulong
    x11.XRootWindow.argtypes = [W.c_void_p, W.c_int]
    x11.XCreateSimpleWindow.restype = W.c_ulong
    x11.XCreateSimpleWindow.argtypes = [W.c_void_p, W.c_ulong, W.c_int, W.c_int,
                                        W.c_uint, W.c_uint, W.c_uint, W.c_ulong, W.c_ulong]
    x11.XMapWindow.argtypes = [W.c_void_p, W.c_ulong]
    x11.XSelectInput.argtypes = [W.c_void_p, W.c_ulong, W.c_long]
    x11.XNextEvent.argtypes = [W.c_void_p, W.c_void_p]
    x11.XFlush.argtypes = [W.c_void_p]
    x11.XStoreName.argtypes = [W.c_void_p, W.c_ulong, W.c_char_p]
    x11.XDisplayWidth.restype = W.c_int
    x11.XDisplayHeight.restype = W.c_int

    dpy = x11.XOpenDisplay(None)
    if not dpy:
        sys.exit("cannot open display")
    scr = x11.XDefaultScreen(dpy)
    root = x11.XRootWindow(dpy, scr)
    dw, dh = x11.XDisplayWidth(dpy, scr), x11.XDisplayHeight(dpy, scr)

    w = h = 160
    # top-right quadrant: if the right-half Y mirror is active, a tap here is
    # reported ~1800 logical px lower and the click will miss the square
    x = int(dw * 0.70)
    y = int(dh * 0.15)
    win = x11.XCreateSimpleWindow(dpy, root, x, y, w, h, 4, 0, 0xFFFFFF)
    x11.XStoreName(dpy, win, b"xtap-target")
    x11.XSelectInput(dpy, win, 4 | 8 | (1 << 15))  # ButtonPress|ButtonRelease|Exposure
    x11.XMapWindow(dpy, win)
    x11.XFlush(dpy)
    print("WIN display=%dx%d window=(%d,%d) size=%dx%d" % (dw, dh, x, y, w, h), flush=True)
    print("TAP THE CENTRE OF THE WHITE SQUARE", flush=True)

    buf = (W.c_long * 24)()
    end = time.time() + 1800
    while time.time() < end:
        x11.XNextEvent(dpy, W.byref(buf))
        ev = W.cast(W.byref(buf), W.POINTER(ButtonEvent)).contents
        if ev.type == 4:  # ButtonPress
            print("CLICK button=%d win=(%d,%d) root=(%d,%d)" %
                  (ev.button, ev.x, ev.y, ev.x_root, ev.y_root), flush=True)


if __name__ == "__main__":
    main()
