#!/usr/bin/env python3
"""cs_perceptual_smooth: red -> blue over one patch, smoothstep in OKLab?"""
from px import load, px
from colour2 import to_oklab, from_oklab

img = load('cs_perceptual_smooth')
w, h, _ = img
a, b = to_oklab((1, 0, 0)), to_oklab((0, 0, 1))
for x in range(0, w, 25):
    u = (x + 0.5) / w
    s = 3 * u * u - 2 * u ** 3
    lab = [a[i] + (b[i] - a[i]) * s for i in range(3)]
    pred = [round(c * 255) for c in from_oklab(lab)]
    print(x, px(img, x, 10)[:3], pred)
