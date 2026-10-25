#!/usr/bin/env python3
"""Paints the clips' photographs: eight landscapes, procedurally, as PNGs.

    python3 make_photos.py OUTPUT_DIRECTORY

The photo library (`materials`) and the image viewers (`images`, `glyphs`)
need pictures that read as photographs at thumbnail size — a sky, a horizon,
something lit — and the repository has none it may show in public. So they
are painted here, the same every run (a seeded noise), and never committed:
regenerate.sh paints them beside the player it stages.

Each is a sky gradient, a sun or a moon, ridges of fractal noise receding into
haze, and water or ground with a reflection — enough structure for the text
renderers' shape matching and dithering to have edges to find.
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 640, 400


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(draw, top, bottom, stops):
    """`stops`: [(fraction, colour)], fractions rising from 0 to 1, over rows `top`..`bottom`."""
    for y in range(top, bottom):
        t = (y - top) / max(1, bottom - top - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                draw.line([(0, y), (WIDTH, y)], fill=lerp(c0, c1, (t - t0) / max(1e-6, t1 - t0)))
                break


def ridge(seed, base, amplitude, roughness=0.55, octaves=6):
    """A skyline: one height per column, from summed sine octaves with seeded phases."""
    rng = random.Random(seed)
    phases = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.6, 1.4)) for _ in range(octaves)]
    heights = []
    for x in range(WIDTH):
        value, weight, frequency = 0.0, 1.0, 1.5 / WIDTH
        for phase, stretch in phases:
            value += weight * math.sin(x * frequency * 2 * math.pi * stretch + phase)
            weight *= roughness
            frequency *= 2.1
        heights.append(base - value * amplitude)
    return heights


def fill_below(draw, heights, colour, bottom=HEIGHT):
    for x, h in enumerate(heights):
        draw.line([(x, int(h)), (x, bottom)], fill=colour)


def disc(draw, centre, radius, colour, glow=None, image=None):
    if glow and image is not None:
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse(
            [centre[0] - radius * 3, centre[1] - radius * 3, centre[0] + radius * 3, centre[1] + radius * 3],
            fill=glow + (90,))
        image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * 1.5)))
        draw = ImageDraw.Draw(image)
    draw.ellipse([centre[0] - radius, centre[1] - radius, centre[0] + radius, centre[1] + radius], fill=colour)
    return draw


def reflect(image, horizon, tint, strength=0.55):
    """Mirrors the picture above `horizon` into the water below it, rippled and tinted."""
    above = image.crop((0, 0, WIDTH, horizon)).transpose(Image.FLIP_TOP_BOTTOM)
    water = Image.new("RGBA", (WIDTH, HEIGHT - horizon), tint + (255,))
    rippled = Image.new("RGBA", above.size)
    for y in range(above.height):
        shift = int(3 * math.sin(y * 0.35))
        rippled.paste(above.crop((0, y, WIDTH, y + 1)), (shift, y))
    water = Image.blend(water, rippled.crop((0, 0, WIDTH, HEIGHT - horizon)), strength)
    image.paste(water, (0, horizon))


def stars(draw, seed, count, below):
    rng = random.Random(seed)
    for _ in range(count):
        x, y = rng.randrange(WIDTH), rng.randrange(below)
        level = rng.randrange(150, 255)
        draw.point((x, y), fill=(level, level, level))


def harbour_at_dawn(image, draw):
    vertical_gradient(draw, 0, 250, [(0, (60, 40, 110)), (0.55, (240, 120, 110)), (1, (255, 200, 120))])
    draw = disc(draw, (430, 230), 34, (255, 230, 170), glow=(255, 170, 100), image=image)
    fill_below(draw, ridge(1, 230, 18), (90, 60, 100), 250)
    fill_below(draw, ridge(2, 244, 8), (50, 35, 70), 250)
    for x in range(60, 260, 38):  # moored masts
        draw.line([(x, 250), (x + 2, 190)], fill=(30, 20, 40), width=2)
        draw.polygon([(x - 14, 250), (x + 18, 250), (x + 12, 258), (x - 8, 258)], fill=(30, 20, 40))
    reflect(image, 250, (90, 60, 110))


def glacier(image, draw):
    vertical_gradient(draw, 0, 260, [(0, (90, 150, 220)), (1, (210, 235, 250))])
    fill_below(draw, ridge(3, 150, 60, roughness=0.6), (235, 245, 255), 260)
    fill_below(draw, ridge(4, 200, 35), (150, 190, 225), 260)
    fill_below(draw, ridge(5, 240, 12), (90, 130, 170), 260)
    reflect(image, 260, (40, 90, 140), strength=0.6)


def dunes(image, draw):
    vertical_gradient(draw, 0, HEIGHT, [(0, (120, 170, 230)), (0.55, (240, 220, 190)), (1, (240, 220, 190))])
    disc(draw, (150, 90), 26, (255, 250, 220))
    for index, (base, colour) in enumerate([(220, (225, 170, 110)), (270, (205, 140, 80)), (330, (175, 105, 60))]):
        fill_below(draw, ridge(10 + index, base, 30 - index * 6, roughness=0.35, octaves=3), colour)


def night_city(image, draw):
    vertical_gradient(draw, 0, 300, [(0, (10, 10, 40)), (1, (60, 30, 90))])
    stars(draw, 7, 160, 200)
    disc(draw, (520, 70), 18, (240, 240, 220))
    rng = random.Random(8)
    x = 0
    while x < WIDTH:  # towers with lit windows
        width, height = rng.randrange(28, 70), rng.randrange(80, 220)
        draw.rectangle([x, 300 - height, x + width, 300], fill=(25, 20, 45))
        for wy in range(300 - height + 8, 296, 10):
            for wx in range(x + 5, x + width - 5, 9):
                if rng.random() < 0.45:
                    draw.rectangle([wx, wy, wx + 4, wy + 5], fill=(255, 210, 120))
        x += width + rng.randrange(2, 10)
    reflect(image, 300, (20, 15, 50), strength=0.5)


def fern_valley(image, draw):
    vertical_gradient(draw, 0, HEIGHT, [(0, (170, 210, 240)), (0.5, (230, 240, 220)), (1, (230, 240, 220))])
    for index, (base, colour) in enumerate([(170, (120, 160, 120)), (220, (70, 130, 70)), (290, (40, 100, 50)),
                                            (360, (20, 70, 35))]):
        fill_below(draw, ridge(20 + index, base, 40 - index * 5), colour)


def lagoon(image, draw):
    vertical_gradient(draw, 0, 210, [(0, (70, 150, 220)), (1, (190, 230, 240))])
    fill_below(draw, ridge(30, 200, 10, roughness=0.4, octaves=3), (40, 110, 80), 215)
    vertical_gradient(draw, 215, HEIGHT, [(0, (40, 200, 190)), (1, (20, 80, 130))])
    for x in range(380, 520, 40):  # palms
        draw.line([(x, 215), (x + 12, 150)], fill=(60, 50, 30), width=4)
        for angle in range(0, 360, 60):
            dx, dy = 28 * math.cos(math.radians(angle)), 12 * math.sin(math.radians(angle))
            draw.line([(x + 12, 150), (x + 12 + dx, 150 + dy)], fill=(30, 110, 50), width=4)


def sunset_orchard(image, draw):
    vertical_gradient(draw, 0, HEIGHT, [(0, (250, 150, 120)), (0.4, (250, 200, 150)), (0.65, (255, 235, 190)), (1, (255, 235, 190))])
    disc(draw, (320, 250), 50, (255, 240, 200))
    fill_below(draw, ridge(40, 255, 6, octaves=3), (120, 80, 70))
    rng = random.Random(41)
    for row, y in enumerate(range(270, HEIGHT + 30, 34)):  # rows of trees
        for x in range(-20 + (row % 2) * 30, WIDTH + 40, 60 + row * 6):
            radius = 10 + row * 4
            draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=(60 + rng.randrange(30), 90, 50))


def aurora(image, draw):
    vertical_gradient(draw, 0, 280, [(0, (5, 10, 30)), (1, (20, 40, 60))])
    stars(draw, 50, 220, 260)
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    curtain = ImageDraw.Draw(layer)
    for x in range(WIDTH):
        top = 60 + 40 * math.sin(x / 70) + 20 * math.sin(x / 23)
        for y in range(int(top), int(top) + 120):
            alpha = int(150 * (1 - (y - top) / 120))
            curtain.point((x, y), fill=(60, 255, 150, alpha))
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(3)))
    draw = ImageDraw.Draw(image)
    fill_below(draw, ridge(51, 270, 25), (10, 20, 30), 280)
    reflect(image, 280, (10, 25, 40), strength=0.6)


PHOTOS = [
    ("harbour-at-dawn", harbour_at_dawn),
    ("glacier", glacier),
    ("dunes", dunes),
    ("night-city", night_city),
    ("fern-valley", fern_valley),
    ("lagoon", lagoon),
    ("orchard", sunset_orchard),
    ("aurora", aurora),
]


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, paint in PHOTOS:
        image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))
        paint(image, ImageDraw.Draw(image))
        image.convert("RGB").filter(ImageFilter.SMOOTH).save(out / f"{name}.png")
    print(f"{len(PHOTOS)} photos -> {out}")


if __name__ == "__main__":
    main()
