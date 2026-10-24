#!/usr/bin/env python3
"""errmap.py NAME W H MOVES [RULE] — mean model error per 20×20 block."""
import sys, math
from px import load, px
from model import build, patch, evaluate, grid

name, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
moves = eval(sys.argv[4])
rule = sys.argv[5] if len(sys.argv) > 5 else 'bisector'
img = load(name)
w, h, _ = img
V = build(grid(W, H, moves), W, H, rule)
P = {(c, r): patch(V, c, r) for r in range(H - 1) for c in range(W - 1)}
for by in range(0, h, 20):
    line = []
    for bx in range(0, w, 20):
        es = []
        for y in range(by, min(h, by + 20)):
            for x in range(bx, min(w, bx + 20)):
                r_, g_, _, a = px(img, x, y)
                U = r_ / 255 * (W - 1)
                Vv = g_ / 255 * (H - 1)
                c, r = min(int(U), W - 2), min(int(Vv), H - 2)
                mx, my = evaluate(P[c, r], U - c, Vv - r)
                es.append(math.hypot(mx * w - (x + .5), my * h - (y + .5)))
        line.append(f'{sum(es) / len(es):4.1f}')
    print(' '.join(line))
