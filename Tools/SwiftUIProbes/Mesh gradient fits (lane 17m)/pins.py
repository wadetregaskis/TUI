#!/usr/bin/env python3
"""Print the SwiftUI pixels the tests pin."""
from px import load, px

pins = {
    'p2x2_linear': [(20, 100), (100, 100), (180, 40)],
    'p2x2_smooth': [(20, 100), (60, 100), (140, 100)],
    'row5_smooth': [(50, 10), (100, 10), (150, 10), (250, 10), (350, 10)],
    'row5_linear': [(50, 10), (150, 10)],
    't_ext': [(74, 5), (250, 5), (126, 5)],
    'cs_perceptual': [(100, 10), (200, 10), (300, 10)],
    'cs_device': [(100, 10), (200, 10)],
    'cs_perceptual_smooth': [(100, 10), (300, 10)],
    'p_hue': [(60, 5), (340, 5), (160, 5)],
    'p_hue_device': [(60, 5), (160, 5)],
    't_alpha_green': [(50, 2), (25, 2)],
    't_alpha': [(50, 2)],
    'bg_blue': [(10, 10), (100, 100), (190, 100)],
    'bg_default': [(10, 10)],
    'bad_count': [(10, 10)],
    'g3_movedxy': [(100, 60), (150, 40), (60, 150), (130, 100), (100, 100)],
    'g3_movedx': [(100, 50), (100, 150), (130, 100)],
    'b2_bow': [(100, 30), (100, 100), (100, 50)],
    's3_centre_smooth': [(75, 75), (75, 25)],
    'doc_small': [(10, 10), (190, 10), (210, 110), (390, 190), (110, 50)],
}
for name, points in pins.items():
    img = load(name)
    print(name, [(x, y, px(img, x, y)) for x, y in points])
