#!/usr/bin/env python3
"""Hypothesis: smooth perceptual colours are Hermite per channel in OKLab's
cube-root LMS (l', m', s'), before its final matrix."""
import math
from px import load, px
from colour import channel_model
from colour2 import RND, lin, enc
from row1d import hermite_row


def to_lms(rgb):
    r, g, b = (lin(x) for x in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    return tuple(math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))


def from_lms(v):
    l, m, s = (x ** 3 for x in v)
    return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))


def row_check(name, colours, rule):
    img = load(name)
    w, h, _ = img
    W = len(colours)
    conv = [to_lms(c) for c in colours]
    fs = [hermite_row([c[ch] for c in conv], rule)[0] for ch in range(3)]
    errs = []
    for x in range(w):
        U = (x + 0.5) / w * (W - 1)
        p = px(img, x, h // 2)
        rgb = from_lms([f(U) for f in fs])
        errs += [abs(rgb[ch] * 255 - p[ch]) for ch in range(3)]
    errs.sort()
    print(f'{name} lms {rule}: rms {math.sqrt(sum(e*e for e in errs)/len(errs)):.2f} max {errs[-1]:.2f}')


def grid_check(name, colours, W, H, rule):
    img = load(name)
    w, hh, _ = img
    conv = [to_lms(c) for c in colours]
    models = [channel_model([[conv[r * W + c][ch] for c in range(W)] for r in range(H)], W, H, rule) for ch in range(3)]
    errs = []
    for y in range(hh):
        for x in range(w):
            p = px(img, x, y)
            rgb = from_lms([m((x + .5) / w * (W - 1), (y + .5) / hh * (H - 1)) for m in models])
            errs += [abs(rgb[ch] * 255 - p[ch]) for ch in range(3)]
    errs.sort()
    print(f'{name} lms {rule}: rms {math.sqrt(sum(e*e for e in errs)/len(errs)):.2f} p95 {errs[int(len(errs)*.95)]:.2f} max {errs[-1]:.2f}')


if __name__ == '__main__':
    fc = dict(limit='fc3')
    row_check('p_hue', [(0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.2, 0.3, 0.9)], fc)
    row_check('p_r1', [(0.34934932, 0.0, 0.60560566), (0.46846843, 0.34334335, 0.7677678),
                       (0.23623621, 0.8058058, 0.9309309), (0.9169169, 0.6116116, 0.34734735)], fc)
    row_check('p_grey', [(v, v, v) for v in (0.2, 0.25, 0.8, 0.8, 0.3)], fc)
    grid_check('t_rand4_perceptual', RND, 4, 4, fc)
    grid_check('t_rand4_perceptual_linear', RND, 4, 4, dict(extremum=False, linear=True))
