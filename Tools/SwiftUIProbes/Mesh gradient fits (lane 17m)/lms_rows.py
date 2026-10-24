#!/usr/bin/env python3
"""Where does the LMS model miss on p_hue / p_r1?"""
from px import load, px
from lms import to_lms, from_lms
from row1d import hermite_row


def show(name, colours):
    img = load(name)
    w, h, _ = img
    W = len(colours)
    conv = [to_lms(c) for c in colours]
    fs = [hermite_row([c[ch] for c in conv], dict(limit='fc3'))[0] for ch in range(3)]
    raw = []
    for x in range(0, w, 10):
        U = (x + 0.5) / w * (W - 1)
        p = px(img, x, h // 2)[:3]
        v = [f(U) for f in fs]
        pred = [round(c * 255) for c in from_lms(v)]
        l, m, s = (q ** 3 for q in v)
        linrgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        flag = '  <--' if max(abs(a - b) for a, b in zip(p, pred)) > 4 else ''
        print(x, p, pred, tuple(round(q, 3) for q in linrgb), flag)


show('p_hue', [(0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.2, 0.3, 0.9)])
