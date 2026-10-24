#!/usr/bin/env python3
"""Candidate models of the smooth colour rule, checked on regular meshes.

For a regular mesh the patch parameters are the pixel's own position, so the
colour model can be checked without the geometry.
"""
import sys, math
from px import load, px


def h(t):
    t2, t3 = t * t, t * t * t
    return (1 - 3 * t2 + 2 * t3, t - 2 * t2 + t3, 3 * t2 - 2 * t3, t3 - t2)


def tangent(prev, c, nxt, rule):
    if prev is None or nxt is None:
        if rule.get('boundary') == 'onesided':
            return (nxt - c) if prev is None else (c - prev)
        return 0.0
    d0, d1 = c - prev, nxt - c
    m = (nxt - prev) / 2
    if rule.get('extremum', True) and d0 * d1 <= 0:
        return 0.0
    lim = rule.get('limit')
    if lim == 'fc3':  # |m| <= 3 min(|d0|, |d1|)
        cap = 3 * min(abs(d0), abs(d1))
        m = max(-cap, min(cap, m))
    elif lim == 'circle':
        a, b = m / d0, m / d1
        s = a * a + b * b
        if s > 9:
            m *= 3 / math.sqrt(s)
    return m


def channel_model(grid, W, H, rule):
    """Return f(U, V) for one channel's vertex grid[r][c]."""
    mu = [[tangent(grid[r][c - 1] if c else None, grid[r][c], grid[r][c + 1] if c < W - 1 else None, rule)
           for c in range(W)] for r in range(H)]
    mv = [[tangent(grid[r - 1][c] if r else None, grid[r][c], grid[r + 1][c] if r < H - 1 else None, rule)
           for c in range(W)] for r in range(H)]
    twist = rule.get('twist', 'zero')

    def tw(r, c):
        if twist == 'zero':
            return 0.0
        # Catmull-Rom style cross derivative from the tangents' differences
        rp, rn = max(0, r - 1), min(H - 1, r + 1)
        if rp == r or rn == r:
            return 0.0
        return (mu[rn][c] - mu[rp][c]) / 2

    def f(U, V):
        c = min(int(U), W - 2)
        r = min(int(V), H - 2)
        u, v = U - c, V - r
        hu, hv = h(u), h(v)
        # Bicubic Hermite: sum over corners of value, du, dv, twist terms.
        val = 0.0
        for (dc, dr) in ((0, 0), (1, 0), (0, 1), (1, 1)):
            wu_val = hu[0] if dc == 0 else hu[2]
            wu_der = hu[1] if dc == 0 else hu[3]
            wv_val = hv[0] if dr == 0 else hv[2]
            wv_der = hv[1] if dr == 0 else hv[3]
            rr, cc = r + dr, c + dc
            val += grid[rr][cc] * wu_val * wv_val
            val += mu[rr][cc] * wu_der * wv_val
            val += mv[rr][cc] * wu_val * wv_der
            val += tw(rr, cc) * wu_der * wv_der
        return val
    return f


def check(name, colours, W, H, rule, channels=(0, 1, 2), quiet=False):
    img = load(name)
    w, hh, _ = img
    models = []
    for ch in range(3):
        grid = [[colours[r * W + c][ch] for c in range(W)] for r in range(H)]
        models.append(channel_model(grid, W, H, rule))
    errs = []
    worst = None
    for y in range(hh):
        for x in range(w):
            p = px(img, x, y)
            U = (x + 0.5) / w * (W - 1)
            V = (y + 0.5) / hh * (H - 1)
            for ch in channels:
                pred = max(0, min(1, models[ch](U, V))) * 255
                e = abs(pred - p[ch])
                errs.append(e)
                if worst is None or e > worst[0]:
                    worst = (e, x, y, ch, pred, p[ch])
    errs.sort()
    rms = math.sqrt(sum(e * e for e in errs) / len(errs))
    if not quiet:
        print(f'{name} {rule}: rms {rms:.2f}, p95 {errs[int(len(errs) * .95)]:.2f}, max {errs[-1]:.2f} at {worst[1:]}')
    return rms


if __name__ == '__main__':
    rules = [
        dict(),
        dict(extremum=False),
        dict(limit='fc3'),
        dict(limit='circle'),
        dict(boundary='onesided'),
        dict(twist='cr'),
    ]
    r = [0.5, 0.52, 0.9, 0.9, 0.5]
    g = [0, 0.5, 1, 0.5, 0]
    b = [0, 0.1, 0.2, 0.6, 1.0]
    row = [(r[i], g[i], b[i]) for i in range(5)]
    for rule in rules:
        check('t_ext', row + row, 5, 2, rule)
    pc = [(0, 0, 0), (1, 0.5, 0), (0, 1, 0)]
    for rule in rules[:2]:
        check('t_perchan', pc + pc, 3, 2, rule)
    gv = [[0.2, 0.6, 0.3], [0.7, 0.4, 0.9], [0.1, 0.8, 0.5]]
    tw = [(c / 2 * r / 2, gv[r][c], 0) for r in range(3) for c in range(3)]
    for rule in rules:
        check('t_twist', tw, 3, 3, rule)
