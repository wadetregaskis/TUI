#!/usr/bin/env python3
"""Print p_hue against models, and the pixel's OKLab."""
from px import load, px
from row1d import predict
from colour2 import to_oklab

hues = [(0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.2, 0.3, 0.9)]
img = load('p_hue')
w, h, _ = img
ok = predict(hues, 'oklab', dict(limit='fc3'))
print('vertex oklab', [tuple(round(v, 3) for v in to_oklab(c)) for c in hues])
for x in range(0, w, 20):
    U = (x + 0.5) / w * 2
    p = px(img, x, 5)[:3]
    lab = to_oklab(tuple(v / 255 for v in p))
    print(x, round(U, 3), p, [round(v * 255) for v in ok(U)], tuple(round(v, 3) for v in lab))
