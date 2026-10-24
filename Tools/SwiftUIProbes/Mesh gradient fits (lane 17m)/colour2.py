#!/usr/bin/env python3
"""Whole-picture checks: a 4×4 mesh of pseudo-random colours, smooth and
bilinear, device and perceptual."""
import math
from px import load, px
from colour import channel_model

RND = [(0.26426423, 0.5835836, 0.042042032), (0.42142138, 0.38038036, 0.9509509),
       (0.4834835, 0.69469476, 0.33833835), (0.8538539, 0.35935932, 0.057057045),
       (0.34934932, 0.0, 0.60560566), (0.46846843, 0.34334335, 0.7677678),
       (0.23623621, 0.8058058, 0.9309309), (0.9169169, 0.6116116, 0.34734735),
       (0.04604604, 0.96196204, 0.17717719), (0.25625625, 0.037037037, 0.29329327),
       (0.34434435, 0.96196204, 0.8978979), (0.43243244, 0.99499506, 0.26326326),
       (0.7227227, 0.10710711, 0.57457465), (0.99899906, 0.8678679, 0.43543544),
       (0.9469469, 0.7207207, 0.5735736), (0.46446443, 0.13613611, 0.46946943)]


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def enc(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_oklab(rgb):
    r, g, b = (lin(x) for x in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def from_oklab(lab):
    L, a, b = lab
    l = L + 0.3963377774 * a + 0.2158037573 * b
    m = L - 0.1055613458 * a - 0.0638541728 * b
    s = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l ** 3, m ** 3, s ** 3
    return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))


def bilinear_model(grid, W, H):
    def f(U, V):
        c = min(int(U), W - 2)
        r = min(int(V), H - 2)
        u, v = U - c, V - r
        return ((1 - u) * (1 - v) * grid[r][c] + u * (1 - v) * grid[r][c + 1]
                + (1 - u) * v * grid[r + 1][c] + u * v * grid[r + 1][c + 1])
    return f


def check(name, colours, W, H, smooth, perceptual):
    img = load(name)
    w, hh, _ = img
    space = [to_oklab(c) for c in colours] if perceptual else colours
    models = []
    for ch in range(3):
        grid = [[space[r * W + c][ch] for c in range(W)] for r in range(H)]
        models.append(channel_model(grid, W, H, dict(limit='fc3')) if smooth else bilinear_model(grid, W, H))
    errs = []
    for y in range(hh):
        for x in range(w):
            p = px(img, x, y)
            U = (x + 0.5) / w * (W - 1)
            V = (y + 0.5) / hh * (H - 1)
            vals = [m(U, V) for m in models]
            rgb = from_oklab(vals) if perceptual else [max(0, min(1, v)) for v in vals]
            for ch in range(3):
                errs.append(abs(rgb[ch] * 255 - p[ch]))
    errs.sort()
    rms = math.sqrt(sum(e * e for e in errs) / len(errs))
    print(f'{name} smooth={smooth} perceptual={perceptual}: rms {rms:.2f}, p95 {errs[int(len(errs)*.95)]:.2f}, max {errs[-1]:.2f}')


if __name__ == '__main__':
    check('t_rand4_linear', RND, 4, 4, False, False)
    check('t_rand4', RND, 4, 4, True, False)
    check('t_rand4_perceptual_linear', RND, 4, 4, False, True)
    check('t_rand4_perceptual', RND, 4, 4, True, True)
    # Cross-checks: the wrong space should be visibly worse.
    check('t_rand4_perceptual', RND, 4, 4, True, False)
    check('t_rand4', RND, 4, 4, False, False)
