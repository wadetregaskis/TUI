#!/usr/bin/env python3
"""A candidate model of SwiftUI's mesh geometry, checked against the probes.

model.py NAME W H RULE      (RULE: bisector | catmull | thirds)
Forward-maps every pixel's encoded (U, V) through the model and reports how
far, in pixels, it lands from the pixel's own centre.
"""
import sys, math
from px import load, px


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def norm(a): return math.hypot(a[0], a[1])


def tangents(prev, p, nxt, rule):
    """(before-cp, after-cp) for vertex p between prev and nxt (either may be None)."""
    if prev is None and nxt is None:
        return p, p
    if prev is None:
        return p, add(p, mul(sub(nxt, p), 1 / 3))
    if nxt is None:
        return add(p, mul(sub(prev, p), 1 / 3)), p
    d1, d2 = norm(sub(p, prev)), norm(sub(nxt, p))
    if rule == 'thirds':
        return add(p, mul(sub(prev, p), 1 / 3)), add(p, mul(sub(nxt, p), 1 / 3))
    if rule == 'catmull':
        t = mul(sub(nxt, prev), 0.5)
        return sub(p, mul(t, 1 / 3)), add(p, mul(t, 1 / 3))
    if rule == 'bisector':
        e = add(mul(sub(p, prev), 1 / d1), mul(sub(nxt, p), 1 / d2))
        n = norm(e)
        e = mul(e, 1 / n)
        return sub(p, mul(e, d1 / 3)), add(p, mul(e, d2 / 3))
    raise ValueError(rule)


def build(points, W, H, rule):
    """points[r][c] -> dict with pos, leading, trailing, top, bottom."""
    V = []
    for r in range(H):
        row = []
        for c in range(W):
            p = points[r][c]
            lead, trail = tangents(points[r][c - 1] if c > 0 else None, p,
                                   points[r][c + 1] if c < W - 1 else None, rule)
            top, bottom = tangents(points[r - 1][c] if r > 0 else None, p,
                                   points[r + 1][c] if r < H - 1 else None, rule)
            row.append(dict(pos=p, leading=lead, trailing=trail, top=top, bottom=bottom))
        V.append(row)
    return V


def patch(V, c, r):
    a, b, d, e = V[r][c], V[r][c + 1], V[r + 1][c], V[r + 1][c + 1]
    P = {}
    P[0, 0], P[3, 0], P[0, 3], P[3, 3] = a['pos'], b['pos'], d['pos'], e['pos']
    P[1, 0], P[2, 0] = a['trailing'], b['leading']
    P[1, 3], P[2, 3] = d['trailing'], e['leading']
    P[0, 1], P[0, 2] = a['bottom'], d['top']
    P[3, 1], P[3, 2] = b['bottom'], e['top']

    def lin(*terms):
        x = sum(k * P[i][0] for k, i in terms)
        y = sum(k * P[i][1] for k, i in terms)
        return (x / 9, y / 9)

    P[1, 1] = lin((-4, (0, 0)), (6, (0, 1)), (6, (1, 0)), (-2, (0, 3)), (-2, (3, 0)), (3, (3, 1)), (3, (1, 3)), (-1, (3, 3)))
    P[1, 2] = lin((-4, (0, 3)), (6, (0, 2)), (6, (1, 3)), (-2, (0, 0)), (-2, (3, 3)), (3, (3, 2)), (3, (1, 0)), (-1, (3, 0)))
    P[2, 1] = lin((-4, (3, 0)), (6, (3, 1)), (6, (2, 0)), (-2, (3, 3)), (-2, (0, 0)), (3, (0, 1)), (3, (2, 3)), (-1, (0, 3)))
    P[2, 2] = lin((-4, (3, 3)), (6, (3, 2)), (6, (2, 3)), (-2, (3, 0)), (-2, (0, 3)), (3, (0, 2)), (3, (2, 0)), (-1, (0, 0)))
    return P


def bern(t):
    s = 1 - t
    return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]


def evaluate(P, u, v):
    bu, bv = bern(u), bern(v)
    x = y = 0.0
    for i in range(4):
        for j in range(4):
            k = bu[i] * bv[j]
            x += k * P[i, j][0]
            y += k * P[i, j][1]
    return x, y


def check(name, points, W, H, rule, V=None):
    img = load(name)
    w, h, _ = img
    V = V or build(points, W, H, rule)
    patches = {(c, r): patch(V, c, r) for r in range(H - 1) for c in range(W - 1)}
    errs = []
    for y in range(h):
        for x in range(w):
            r_, g_, _, a = px(img, x, y)
            if a < 255:
                continue
            U = r_ / 255 * (W - 1)
            Vv = g_ / 255 * (H - 1)
            c, r = min(int(U), W - 2), min(int(Vv), H - 2)
            u, v = U - c, Vv - r
            mx, my = evaluate(patches[c, r], u, v)
            errs.append(math.hypot(mx * w - (x + 0.5), my * h - (y + 0.5)))
    errs.sort()
    rms = math.sqrt(sum(e * e for e in errs) / len(errs))
    print(f'{name} {rule}: rms {rms:.2f} px, median {errs[len(errs)//2]:.2f}, p95 {errs[int(len(errs)*.95)]:.2f}, max {errs[-1]:.2f}')


def grid(W, H, moves):
    pts = [[(c / (W - 1), r / (H - 1)) for c in range(W)] for r in range(H)]
    for (c, r), p in moves.items():
        pts[r][c] = p
    return pts


if __name__ == '__main__':
    cases = {
        'g3_regular': (3, 3, {}),
        'g3_movedx': (3, 3, {(1, 1): (0.7, 0.5)}),
        'g3_movedxy': (3, 3, {(1, 1): (0.7, 0.3)}),
        'g3_movededge': (3, 3, {(1, 0): (0.7, 0.0)}),
        'g4_moved': (4, 4, {(1, 1): (0.5, 0.2)}),
    }
    for name, (W, H, moves) in cases.items():
        for rule in ('thirds', 'catmull', 'bisector'):
            check(name, grid(W, H, moves), W, H, rule)
