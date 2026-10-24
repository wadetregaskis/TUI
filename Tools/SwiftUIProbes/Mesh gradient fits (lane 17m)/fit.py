#!/usr/bin/env python3
"""Fit a bicubic Bézier patch to the (U, V) the colours encode.

fit.py NAME W H PATCH_COL PATCH_ROW
For a mesh of W×H vertices drawn with coordColours, every pixel's red is
U = col/(W-1) and green V = row/(H-1). Pixels inside the given patch give
(u, v) in that patch; least squares solves the 16 control points of the
tensor-product patch that maps (u, v) to the pixel centre in unit space.
"""
import sys
from px import load, px


def bern(t):
    s = 1 - t
    return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]


def solve(a, b):
    n = len(a)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[piv] = m[piv], m[col]
        p = m[col][col]
        for r in range(n):
            if r != col:
                f = m[r][col] / p
                for k in range(col, n + 1):
                    m[r][k] -= f * m[col][k]
    return [m[i][n] / m[i][i] for i in range(n)]


def fit(name, W, H, pc, pr):
    img = load(name)
    w, h, _ = img
    rows = []
    for y in range(h):
        for x in range(w):
            r, g, _, a = px(img, x, y)
            if a < 255:
                continue
            U = r / 255 * (W - 1)
            V = g / 255 * (H - 1)
            u, v = U - pc, V - pr
            if not (0.03 < u < 0.97 and 0.03 < v < 0.97):
                continue
            bu, bv = bern(u), bern(v)
            basis = [bu[i] * bv[j] for j in range(4) for i in range(4)]
            rows.append((basis, (x + 0.5) / w, (y + 0.5) / h))
    n = 16
    ata = [[0.0] * n for _ in range(n)]
    atx = [0.0] * n
    aty = [0.0] * n
    for basis, X, Y in rows:
        for i in range(n):
            bi = basis[i]
            atx[i] += bi * X
            aty[i] += bi * Y
            for j in range(n):
                ata[i][j] += bi * basis[j]
    cx = solve(ata, atx)
    cy = solve(ata, aty)
    print(f'{name} patch ({pc},{pr}) from {len(rows)} px; control points P[i][j], i along u, j along v:')
    for j in range(4):
        print('  ' + '  '.join(f'({cx[j*4+i]:.4f},{cy[j*4+i]:.4f})' for i in range(4)))
    return cx, cy


if __name__ == '__main__':
    name, W, H, pc, pr = sys.argv[1], *map(int, sys.argv[2:6])
    fit(name, W, H, pc, pr)
