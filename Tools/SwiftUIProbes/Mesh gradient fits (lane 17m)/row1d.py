#!/usr/bin/env python3
"""1-D smooth colour models for a row mesh (W×2, regular), compared with a probe."""
import math, sys
from px import load, px
from colour import tangent
from colour2 import to_oklab, from_oklab, lin, enc


def hermite_row(vals, rule):
    W = len(vals)
    m = [tangent(vals[i - 1] if i else None, vals[i], vals[i + 1] if i < W - 1 else None, rule) for i in range(W)]

    def f(U):
        i = min(int(U), W - 2)
        t = U - i
        t2, t3 = t * t, t * t * t
        return ((1 - 3 * t2 + 2 * t3) * vals[i] + (t - 2 * t2 + t3) * m[i]
                + (3 * t2 - 2 * t3) * vals[i + 1] + (t3 - t2) * m[i + 1])
    return f, m


def predict(colours, space, rule, tangent_space=None):
    """Per-channel Hermite in `space`; tangents' limiting decided in tangent_space."""
    W = len(colours)
    if space == 'oklab':
        conv = [to_oklab(c) for c in colours]
        back = from_oklab
    else:
        conv = colours
        back = lambda v: [max(0, min(1, x)) for x in v]
    fs = [hermite_row([c[ch] for c in conv], rule)[0] for ch in range(3)]
    return lambda U: back([f(U) for f in fs])


def weights_model(colours, rule):
    """Hermite weights computed in DEVICE space per channel... then mixing in OKLab
    is not defined per channel; instead: compute device-space smooth result, then
    nothing. Placeholder."""
    raise NotImplementedError


def compare(name, colours, models):
    img = load(name)
    w, h, _ = img
    W = len(colours)
    for label, model in models:
        errs = []
        for x in range(w):
            U = (x + 0.5) / w * (W - 1)
            p = px(img, x, h // 2)
            rgb = model(U)
            errs += [abs(rgb[ch] * 255 - p[ch]) for ch in range(3)]
        errs.sort()
        rms = math.sqrt(sum(e * e for e in errs) / len(errs))
        print(f'{name} {label}: rms {rms:.2f} max {errs[-1]:.2f}')


if __name__ == '__main__':
    fc = dict(limit='fc3')
    greys = [(v, v, v) for v in (0.2, 0.25, 0.8, 0.8, 0.3)]
    compare('p_grey', greys, [('oklab', predict(greys, 'oklab', fc)), ('device', predict(greys, 'device', fc))])
    compare('p_grey_device', greys, [('oklab', predict(greys, 'oklab', fc)), ('device', predict(greys, 'device', fc))])
    g2 = [(v, v, v) for v in (0.1, 0.3, 0.5, 0.7, 0.9)]
    compare('p_grey2', g2, [('oklab', predict(g2, 'oklab', fc)), ('device', predict(g2, 'device', fc))])
    hues = [(0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.2, 0.3, 0.9)]
    compare('p_hue', hues, [('oklab', predict(hues, 'oklab', fc)), ('device', predict(hues, 'device', fc))])
    compare('p_hue_device', hues, [('oklab', predict(hues, 'oklab', fc)), ('device', predict(hues, 'device', fc))])
    r1 = [(0.34934932, 0.0, 0.60560566), (0.46846843, 0.34334335, 0.7677678),
          (0.23623621, 0.8058058, 0.9309309), (0.9169169, 0.6116116, 0.34734735)]
    compare('p_r1', r1, [('oklab', predict(r1, 'oklab', fc)), ('device', predict(r1, 'device', fc))])
    compare('p_r1_device', r1, [('oklab', predict(r1, 'oklab', fc)), ('device', predict(r1, 'device', fc))])
