#!/usr/bin/env python3
"""Paints the Example's demo picture, Sources/Example/Resources/demo-image.jpg.

    python3 paint_demo_image.py OUTPUT.jpg

An orrery badge on a starfield: a brushed-metal disc with an engraved scale,
a glowing blue field scattered with lights, and a ringed planet at its centre.
Painted rather than photographed so the repository holds nothing it may not
show, and the same every run (seeded noise).

What the image demo pages and the palette tests need from it, and so what it
keeps of the picture it replaced: near-black ground with fine specks (the
text renderers' dithering), a large neutral grey surface with a gradient and
grain (a palette's greys, which must not invent a hue), saturated blues
from navy to near-white (a ramp a 16- or 256-colour palette must spend
entries on), a warm accent against them, and hard edges at several scales.
"""
import math
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1100, 1080
CX, CY = WIDTH // 2, HEIGHT // 2 + 10
DISC = 400          # the metal disc's radius
FIELD = 262         # the blue field's radius
RIM = 14            # the bevel between them


def radial_mask(radius, feather=0):
    """A white disc of `radius` at the centre, feathered by `feather` pixels."""
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(mask).ellipse([CX - radius, CY - radius, CX + radius, CY + radius], fill=255)
    return mask.filter(ImageFilter.GaussianBlur(feather)) if feather else mask


def starfield(rng):
    sky = Image.new("RGB", (WIDTH, HEIGHT), (3, 4, 9))
    # A faint violet haze across one corner, so the ground is not one colour.
    haze = Image.new("RGB", (WIDTH, HEIGHT), (34, 22, 58))
    haze_mask = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(haze_mask).ellipse([-500, 560, 520, 1500], fill=90)
    sky.paste(haze, (0, 0), haze_mask.filter(ImageFilter.GaussianBlur(160)))
    draw = ImageDraw.Draw(sky)
    for _ in range(2600):
        x, y = rng.randrange(WIDTH), rng.randrange(HEIGHT)
        level = int(70 + 185 * rng.random() ** 3)
        tint = rng.choice([(0, 0, 0), (-20, -10, 10), (10, 0, -25)])
        colour = tuple(max(0, min(255, level + t)) for t in tint)
        if rng.random() < 0.04:
            draw.ellipse([x - 1, y - 1, x + 1, y + 1], fill=colour)
        else:
            draw.point((x, y), fill=colour)
    return sky


def brushed_metal(rng):
    """A grey-blue disc lit from the upper left, brushed in circles."""
    metal = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = metal.load()
    # Brushing: a grain that runs along the circles, i.e. varies with the
    # radius and barely with the angle — a 1-D noise over the radius, plus a
    # finer per-pixel speckle.
    grain = [rng.gauss(0, 1) for _ in range(DISC + 2)]
    for _ in range(3):
        grain = [(grain[max(0, i - 1)] + grain[i] + grain[min(len(grain) - 1, i + 1)]) / 3
                 for i in range(len(grain))]
    for y in range(CY - DISC, CY + DISC + 1):
        for x in range(CX - DISC, CX + DISC + 1):
            dx, dy = x - CX, y - CY
            r = math.hypot(dx, dy)
            if r > DISC:
                continue
            # Light from the upper left: brighter where the normal faces it.
            light = 0.5 - 0.5 * (dx * 0.62 + dy * 0.78) / DISC
            # Anisotropic sheen: brushed metal throws a bright band
            # across the disc at right angles to the light.
            angle = math.atan2(dy, dx)
            sheen = 0.18 * math.cos(2 * (angle + 0.9)) ** 8
            base = 92 + 120 * light + 70 * sheen
            g = grain[int(r)] * 9 + rng.gauss(0, 3.2)
            v = base + g
            pixels[x, y] = (int(max(0, min(255, v - 6))),
                            int(max(0, min(255, v))),
                            int(max(0, min(255, v + 12))))
    return metal


def engrave_scale(metal):
    """Tick marks around the disc's edge: a dark cut with a lit lower lip."""
    draw = ImageDraw.Draw(metal)
    for i in range(72):
        angle = 2 * math.pi * i / 72
        long_tick = i % 6 == 0
        inner = DISC - (46 if long_tick else 26)
        outer = DISC - 12
        width = 5 if long_tick else 3
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for offset, colour in ((1.6, (215, 222, 232)), (0.0, (38, 42, 52))):
            ox, oy = offset * 0.6, offset * 0.8
            draw.line([(CX + inner * cos_a + ox, CY + inner * sin_a + oy),
                       (CX + outer * cos_a + ox, CY + outer * sin_a + oy)],
                      fill=colour, width=width)
    # Two engraved rings bounding the scale.
    for radius in (DISC - 10, DISC - 54):
        draw.ellipse([CX - radius + 1, CY - radius + 1, CX + radius + 1, CY + radius + 1],
                     outline=(210, 216, 226), width=2)
        draw.ellipse([CX - radius, CY - radius, CX + radius, CY + radius],
                     outline=(40, 44, 56), width=2)


def blue_field(rng):
    """The inner field: navy at the centre to a bright rim, with lights."""
    field = Image.new("RGB", (WIDTH, HEIGHT), (4, 10, 40))
    draw = ImageDraw.Draw(field)
    for radius in range(FIELD, 0, -2):
        t = radius / FIELD
        glow = t ** 6
        colour = (int(6 + 40 * glow), int(16 + 120 * glow), int(52 + 200 * glow))
        draw.ellipse([CX - radius, CY - radius, CX + radius, CY + radius], fill=colour)
    # A bright inner ring, then a thin dark one, as a lens's edge would show.
    draw.ellipse([CX - FIELD + 18, CY - FIELD + 18, CX + FIELD - 18, CY + FIELD - 18],
                 outline=(120, 200, 255), width=3)
    draw.ellipse([CX - FIELD + 24, CY - FIELD + 24, CX + FIELD - 24, CY + FIELD - 24],
                 outline=(8, 20, 70), width=2)
    # Lights: small glass beads, each a bright dot with a darker shadow.
    for _ in range(70):
        r = FIELD * 0.82 * math.sqrt(rng.random())
        a = rng.random() * 2 * math.pi
        x, y = CX + r * math.cos(a), CY + r * math.sin(a)
        size = rng.choice([2, 3, 3, 4, 5])
        draw.ellipse([x - size + 1, y - size + 2, x + size + 1, y + size + 2], fill=(4, 8, 30))
        draw.ellipse([x - size, y - size, x + size, y + size], fill=(90, 170, 255))
        draw.ellipse([x - size / 2, y - size / 2 - 1, x, y - 1], fill=(225, 245, 255))
    return field


def planet(canvas):
    """A ringed planet, amber, lit from the upper left, its ring tilted."""
    radius = 92
    ring_a, ring_b, tilt = 210, 54, -0.38

    def draw_ring(front_only):
        # Each band an annulus, drawn as a mask at four times the size and
        # brought down, so the tilted edges are smooth. The whole ring goes
        # behind the planet and only its near half in front, over the same
        # pixels, so the two meet without a seam.
        ss = 4
        for outer, inner, colour in ((1.0, 0.9, (246, 214, 140)), (0.9, 0.83, (180, 132, 62)),
                                     (0.83, 0.72, (232, 196, 120))):
            mask = Image.new("L", (WIDTH * ss, HEIGHT * ss), 0)
            draw = ImageDraw.Draw(mask)
            for scale, fill in ((outer, 255), (inner, 0)):
                a, b = ring_a * scale * ss, ring_b * scale * ss
                draw.ellipse([CX * ss - a, CY * ss - b, CX * ss + a, CY * ss + b], fill=fill)
            if front_only:
                draw.rectangle([0, 0, WIDTH * ss, CY * ss], fill=0)
            mask = mask.rotate(math.degrees(tilt), center=(CX * ss, CY * ss), resample=Image.BICUBIC)
            canvas.paste(Image.new("RGBA", (WIDTH, HEIGHT), colour + (255,)), (0, 0),
                         mask.resize((WIDTH, HEIGHT), Image.BOX))

    draw_ring(front_only=False)
    body = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    pixels = body.load()
    for y in range(CY - radius, CY + radius + 1):
        for x in range(CX - radius, CX + radius + 1):
            dx, dy = (x - CX) / radius, (y - CY) / radius
            d2 = dx * dx + dy * dy
            if d2 > 1:
                continue
            dz = math.sqrt(1 - d2)
            light = max(0.0, -0.55 * dx - 0.6 * dy + 0.58 * dz)
            # Bands of latitude, bent by the tilt.
            band = 0.5 + 0.5 * math.sin((dy - 0.38 * dx) * 13)
            shade = 0.18 + 0.95 * light
            r = (196 + 40 * band) * shade
            g = (120 + 46 * band) * shade
            b = (52 + 22 * band) * shade
            edge = min(1.0, (1 - d2) * 40)
            pixels[x, y] = (int(min(255, r)), int(min(255, g)), int(min(255, b)), int(255 * edge))
    canvas.alpha_composite(body)
    draw_ring(front_only=True)


def glow(canvas, radius, colour, blur, strength):
    layer = Image.new("RGB", (WIDTH, HEIGHT), colour)
    mask = radial_mask(radius).point(lambda v: v * strength // 255).filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(layer, (0, 0), mask)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rng = random.Random(1966)
    picture = starfield(rng)
    # A soft shadow under the disc, then the disc.
    shadow = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    picture.paste(shadow, (14, 22), radial_mask(DISC, 18).point(lambda v: v * 200 // 255))
    metal = brushed_metal(rng)
    engrave_scale(metal)
    picture.paste(metal, (0, 0), radial_mask(DISC, 1))
    # The bevel: a dark lip on the lit side, a bright one opposite.
    bevel = ImageDraw.Draw(picture)
    for offset, colour in ((-3, (24, 28, 40)), (3, (226, 232, 242))):
        r = FIELD + RIM
        bevel.ellipse([CX - r + offset, CY - r + offset, CX + r + offset, CY + r + offset],
                      outline=colour, width=4)
    picture.paste(blue_field(rng), (0, 0), radial_mask(FIELD + RIM - 4, 1))
    glow(picture, FIELD + RIM, (60, 150, 255), 22, 70)
    canvas = picture.convert("RGBA")
    planet(canvas)
    picture = canvas.convert("RGB")
    # A specular highlight on the metal, upper left.
    highlight = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(highlight).ellipse([CX - 330, CY - 360, CX - 90, CY - 250], fill=70)
    highlight = ImageChops.multiply(highlight.filter(ImageFilter.GaussianBlur(40)), radial_mask(DISC))
    picture.paste(Image.new("RGB", (WIDTH, HEIGHT), (255, 255, 255)), (0, 0), highlight)
    picture.save(sys.argv[1], quality=90, optimize=True)


if __name__ == "__main__":
    main()
