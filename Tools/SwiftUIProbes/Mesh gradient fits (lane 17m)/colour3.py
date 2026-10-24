#!/usr/bin/env python3
"""Smooth + perceptual: which rule?"""
import math, sys
from px import load, px
from colour import channel_model
from colour2 import RND, to_oklab, from_oklab, lin, enc


def check(name, colours, W, H, rule, label, space='oklab'):
    img = load(name)
    w, hh, _ = img
    if space == 'oklab':
        conv = [to_oklab(c) for c in colours]
        back = from_oklab
    elif space == 'linear':
        conv = [tuple(lin(x) for x in c) for c in colours]
        back = lambda v: [enc(x) for x in v]
    else:
        conv = colours
        back = lambda v: [max(0, min(1, x)) for x in v]
    models = []
    for ch in range(3):
        grid = [[conv[r * W + c][ch] for c in range(W)] for r in range(H)]
        models.append(channel_model(grid, W, H, rule))
    errs = []
    for y in range(hh):
        for x in range(w):
            p = px(img, x, y)
            U = (x + 0.5) / w * (W - 1)
            V = (y + 0.5) / hh * (H - 1)
            rgb = back([m(U, V) for m in models])
            for ch in range(3):
                errs.append(abs(rgb[ch] * 255 - p[ch]))
    errs.sort()
    rms = math.sqrt(sum(e * e for e in errs) / len(errs))
    print(f'{name} {label} {space}: rms {rms:.2f}, p95 {errs[int(len(errs)*.95)]:.2f}, max {errs[-1]:.2f}')


if __name__ == '__main__':
    for label, rule in [('fc3', dict(limit='fc3')), ('none', dict(extremum=False)),
                        ('extremum only', dict()), ('onesided', dict(boundary='onesided', limit='fc3'))]:
        check('t_rand4_perceptual', RND, 4, 4, rule, label)
    check('t_rand4_perceptual', RND, 4, 4, dict(limit='fc3'), 'fc3', space='linear')
    check('t_rand4', RND, 4, 4, dict(limit='fc3'), 'fc3', space='linear')
