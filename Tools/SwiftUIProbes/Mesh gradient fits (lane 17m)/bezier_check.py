#!/usr/bin/env python3
"""Check the explicit bezierPoints: probes against the Coons-patch model."""
from model import check


def bp(p, l, t, r, b):
    return dict(pos=p, leading=l, top=t, trailing=r, bottom=b)


cases = {
    'b2_bow': [
        bp((0, 0), (0, 0), (0, 0), (0.33, 0.5), (0, 0.33)),
        bp((1, 0), (0.67, 0.5), (1, 0), (1, 0), (1, 0.33)),
        bp((0, 1), (0, 1), (0, 0.67), (0.33, 1), (0, 1)),
        bp((1, 1), (0.67, 1), (1, 0.67), (1, 1), (1, 1)),
    ],
    'b2_straight': [
        bp((0, 0), (0, 0), (0, 0), (0.33, 0), (0, 0.33)),
        bp((1, 0), (0.67, 0), (1, 0), (1, 0), (1, 0.33)),
        bp((0, 1), (0, 1), (0, 0.67), (0.33, 1), (0, 1)),
        bp((1, 1), (0.67, 1), (1, 0.67), (1, 1), (1, 1)),
    ],
    'b2_bunched': [
        bp((0, 0), (0, 0), (0, 0), (0.05, 0), (0, 0.33)),
        bp((1, 0), (0.1, 0), (1, 0), (1, 0), (1, 0.33)),
        bp((0, 1), (0, 1), (0, 0.67), (0.05, 1), (0, 1)),
        bp((1, 1), (0.1, 1), (1, 0.67), (1, 1), (1, 1)),
    ],
}
for name, pts in cases.items():
    V = [[pts[0], pts[1]], [pts[2], pts[3]]]
    check(name, None, 2, 2, 'explicit', V=V)
