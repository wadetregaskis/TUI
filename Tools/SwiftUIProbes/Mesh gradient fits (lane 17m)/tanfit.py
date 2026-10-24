#!/usr/bin/env python3
"""Least-squares fit of every vertex tangent, per channel, for a W×2 row mesh,
in OKLab or device space. tanfit.py NAME SPACE c0 c1 ... (colours as r,g,b)."""
import sys
from px import load, px
from colour2 import to_oklab
from fit import solve


def fit(name, colours, space):
    img = load(name)
    w, h, _ = img
    W = len(colours)
    conv = (lambda c: to_oklab(c)) if space == 'oklab' else (lambda c: c)
    verts = [conv(c) for c in colours]
    out = []
    for ch in range(3):
        n = W
        ata = [[0.0] * n for _ in range(n)]
        atb = [0.0] * n
        for x in range(w):
            U = (x + 0.5) / w * (W - 1)
            i = min(int(U), W - 2)
            t = U - i
            t2, t3 = t * t, t ** 3
            h00, h10, h01, h11 = 1 - 3 * t2 + 2 * t3, t - 2 * t2 + t3, 3 * t2 - 2 * t3, t3 - t2
            p = px(img, x, h // 2)[:3]
            val = conv(tuple(v / 255 for v in p))[ch]
            rhs = val - h00 * verts[i][ch] - h01 * verts[i + 1][ch]
            row = [0.0] * n
            row[i] = h10
            row[i + 1] = h11
            for a in range(n):
                atb[a] += row[a] * rhs
                for b in range(n):
                    ata[a][b] += row[a] * row[b]
        for a in range(n):
            ata[a][a] += 1e-9
        out.append(solve(ata, atb))
    print(f'{name} {space}: vertices {[tuple(round(v, 4) for v in c) for c in verts]}')
    for ch in range(3):
        vals = [verts[i][ch] for i in range(W)]
        cr = ['-'] + [round((vals[i + 1] - vals[i - 1]) / 2, 4) for i in range(1, W - 1)] + ['-']
        print(f'  ch{ch}: fitted {[round(m, 4) for m in out[ch]]}  CR {cr}')


if __name__ == '__main__':
    hues = [(0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.2, 0.3, 0.9)]
    fit('p_hue', hues, 'oklab')
    fit('p_hue_device', hues, 'device')
    r1 = [(0.34934932, 0.0, 0.60560566), (0.46846843, 0.34334335, 0.7677678),
          (0.23623621, 0.8058058, 0.9309309), (0.9169169, 0.6116116, 0.34734735)]
    fit('p_r1', r1, 'oklab')
    fit('p_r1_device', r1, 'device')
    greys = [(v, v, v) for v in (0.2, 0.25, 0.8, 0.8, 0.3)]
    fit('p_grey', greys, 'oklab')
