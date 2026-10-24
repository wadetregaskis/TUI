#!/usr/bin/env python3
"""Read the probe's RGBA dumps. px.py NAME [x y]... or px.py NAME row Y [step] / col X [step]."""
import sys, os

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')


def load(name):
    w, h = map(int, open(f'{D}/{name}.txt').read().split())
    b = open(f'{D}/{name}.rgba', 'rb').read()
    return w, h, b


def px(img, x, y):
    w, h, b = img
    i = (y * w + x) * 4
    r, g, bl, a = b[i:i + 4]
    if a and a != 255:  # unpremultiply
        r, g, bl = (round(v * 255 / a) for v in (r, g, bl))
    return (r, g, bl, a)


if __name__ == '__main__':
    name = sys.argv[1]
    img = load(name)
    w, h, _ = img
    args = sys.argv[2:]
    if args and args[0] == 'row':
        y = int(args[1]); step = int(args[2]) if len(args) > 2 else 10
        for x in range(0, w, step):
            print(x, px(img, x, y))
    elif args and args[0] == 'col':
        x = int(args[1]); step = int(args[2]) if len(args) > 2 else 10
        for y in range(0, h, step):
            print(y, px(img, x, y))
    else:
        it = iter(args)
        for x, y in zip(it, it):
            print(x, y, px(img, int(x), int(y)))
