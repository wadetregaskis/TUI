#!/usr/bin/env python3
"""Draw the Example's animated picture, `Sources/Example/Resources/bouncing-ball.gif`.

    python3 Tools/ExampleImages/make_bouncing_ball.py [OUTPUT.gif]

A shaded, lit, chequered ball bouncing on a chequered floor that runs off to a
hazy horizon, with a soft shadow under it: drawn here, procedurally, so the
picture has no author but this script and no licence to keep track of.

What it is for: the image page's animated picture, which the owner asked
(2026-11-10, item 24) to show what a terminal's graphics protocol draws that
glyphs cannot. So it is made of what glyphs lose and pixels keep, at 320 x 200,
well above any terminal's cell grid:

- smooth gradients: the sky, the ball's shading and its highlight;
- fine detail: the floor's squares shrinking towards the horizon, finer than a
  cell long before they reach it, and the ball's squares turning;
- smooth motion: the ball's height changes by fractions of a cell per frame,
  and it squashes as it lands.

The last picture, a ball of 80 x 40 pixel art, looked the same either way.

GIF, because GIF is the one animated format every platform TUI runs on can
play (`AnimatedImageDecoder`: ImageIO on Apple's, stb_image elsewhere, which
reads no APNG or WebP animation). A GIF frame has 256 colours, so all the frames
share one palette, chosen from all of them: a pixel of the background that did
not change is then the same colour in every frame, and each frame stores only the
box the ball and its shadow moved through. Not dithered: 256 colours already
draw these gradients without visible steps at this size, and a dither cost a
third more bytes and spent palette entries on its own noise.

Thirty frames a second, as near as a GIF can say: delays of 30, 30 and 40 ms in
turn, which change the frame on every second tick of a 60 Hz frame clock (the
frame clock rounds a wake up to its next tick: 30 ms is the tick at 33.3, 60 is
66.7, and 100 is 100). Twenty-four frames, so one bounce is 0.8 s, and the ball
turns by exactly one of its squares in that time, so the loop has no seam.

Needs Pillow (as the terminal probes do; written with 11.3). Deterministic: the same script draws
the same bytes.
"""
import math
import sys

from PIL import Image

WIDTH, HEIGHT = 320, 200
FRAMES = 24
DELAYS_MS = [30, 30, 40] * (FRAMES // 3)

HORIZON = 78  # the screen row the floor meets the sky at
CAMERA_HEIGHT = 1.6  # world units above the floor
FOCAL = 260.0  # pixels
TILE = 0.9  # a floor square, in world units

BALL_X = WIDTH / 2
BALL_RADIUS = 30.0
FLOOR_Y = 176.0  # the screen row the ball touches the floor at
BOUNCE = 92.0  # how high the ball's bottom rises, in pixels

SKY_TOP = (22, 34, 92)
SKY_HORIZON = (250, 196, 150)
FLOOR_LIGHT = (232, 226, 210)
FLOOR_DARK = (40, 112, 120)
BALL_RED = (214, 28, 40)
BALL_WHITE = (246, 244, 238)

LIGHT = (-0.45, -0.65, 0.62)  # towards the light: left, up, towards the viewer


def normalised(vector):
    length = math.sqrt(sum(c * c for c in vector))
    return tuple(c / length for c in vector)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def floor_colour(sx, sy):
    """The floor at screen point (sx, sy), below the horizon: its square, faded
    into the haze by distance."""
    depth = CAMERA_HEIGHT * FOCAL / (sy - HORIZON)
    x = (sx - WIDTH / 2) * depth / FOCAL
    square = (math.floor(x / TILE) + math.floor(depth / TILE)) % 2
    colour = FLOOR_LIGHT if square else FLOOR_DARK
    haze = 1 - math.exp(-depth / 28.0)
    return mix(colour, SKY_HORIZON, haze)


def sky_colour(sy):
    t = (sy / HORIZON) ** 1.4
    return mix(SKY_TOP, SKY_HORIZON, t)


def background():
    """Sky and floor, each pixel the average of a 4 x 4 grid of samples, so the
    squares near the horizon blend rather than alias."""
    samples = 4
    pixels = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            total = [0.0, 0.0, 0.0]
            for j in range(samples):
                sy = y + (j + 0.5) / samples
                for i in range(samples):
                    sx = x + (i + 0.5) / samples
                    colour = floor_colour(sx, sy) if sy > HORIZON + 0.5 else sky_colour(sy)
                    for c in range(3):
                        total[c] += colour[c]
            pixels.append(tuple(v / (samples * samples) for v in total))
    return pixels


def ball_state(frame):
    """The ball's centre, its squash (x and y scale) and its turn, at `frame`."""
    t = frame / FRAMES
    height = BOUNCE * 4 * t * (1 - t)
    # Squashed while it is within a few pixels of the floor, by how near.
    nearness = max(0.0, 1 - height / 10.0)
    squash = 0.16 * nearness * nearness
    scale_x, scale_y = 1 + squash, 1 - squash
    centre_y = FLOOR_Y - BALL_RADIUS * scale_y - height
    turn = t * (2 * math.pi / 12)  # one square of twelve round the ball per loop
    return centre_y, scale_x, scale_y, turn, height


def ball_sample(dx, dy, turn):
    """The ball's colour at (dx, dy) from its centre, as a unit sphere's, or
    `None` off it."""
    rr = dx * dx + dy * dy
    if rr > 1:
        return None
    nz = math.sqrt(1 - rr)
    normal = (dx, dy, nz)
    # Tilted towards the viewer, so the top cap shows, and turned about its axis.
    tilt = 0.35
    y1 = normal[1] * math.cos(tilt) - normal[2] * math.sin(tilt)
    z1 = normal[1] * math.sin(tilt) + normal[2] * math.cos(tilt)
    longitude = math.atan2(normal[0], z1) + turn
    latitude = math.asin(max(-1.0, min(1.0, -y1)))
    square = (math.floor(longitude / (2 * math.pi / 12)) + math.floor(latitude / (math.pi / 6))) % 2
    albedo = BALL_RED if square else BALL_WHITE
    light = normalised(LIGHT)
    diffuse = max(0.0, sum(n * l for n, l in zip(normal, light)))
    half = normalised((light[0], light[1], light[2] + 1))
    specular = max(0.0, sum(n * h for n, h in zip(normal, half))) ** 60
    # The sky's glow round the rim, and the floor's light bounced up underneath.
    rim = (1 - nz) ** 3
    bounce = max(0.0, dy) * 0.25
    colour = []
    for c in range(3):
        lit = albedo[c] * (0.16 + 0.84 * diffuse) + SKY_HORIZON[c] * (0.35 * rim + bounce * 0.4)
        colour.append(min(255.0, lit + 255 * 0.85 * specular))
    return tuple(colour)


def draw_frame(base, frame):
    pixels = list(base)
    centre_y, scale_x, scale_y, turn, height = ball_state(frame)

    # The shadow: an ellipse on the floor under the ball, wider, fainter and
    # softer the higher the ball is.
    spread = 1 + height / 70.0
    radius_x = BALL_RADIUS * 1.05 * spread * scale_x
    radius_y = radius_x * 0.22
    darkness = 0.55 / (spread * spread)
    softness = 0.35 + 0.4 * (spread - 1)
    for y in range(int(FLOOR_Y - radius_y * 2) - 1, min(HEIGHT, int(FLOOR_Y + radius_y * 2) + 2)):
        for x in range(int(BALL_X - radius_x * 2) - 1, int(BALL_X + radius_x * 2) + 2):
            d = math.hypot((x + 0.5 - BALL_X) / radius_x, (y + 0.5 - FLOOR_Y) / radius_y)
            edge = min(1.0, max(0.0, (1 + softness - d) / (2 * softness)))
            shade = darkness * edge * edge * (3 - 2 * edge)
            if shade > 0:
                index = y * WIDTH + x
                pixels[index] = tuple(c * (1 - shade) for c in pixels[index])

    # The ball, each pixel the average of 3 x 3 samples, for its edge.
    samples = 3
    rx, ry = BALL_RADIUS * scale_x, BALL_RADIUS * scale_y
    for y in range(int(centre_y - ry) - 1, int(centre_y + ry) + 2):
        for x in range(int(BALL_X - rx) - 1, int(BALL_X + rx) + 2):
            total = [0.0, 0.0, 0.0]
            covered = 0
            for j in range(samples):
                for i in range(samples):
                    dx = (x + (i + 0.5) / samples - BALL_X) / rx
                    dy = (y + (j + 0.5) / samples - centre_y) / ry
                    colour = ball_sample(dx, dy, turn)
                    if colour is None:
                        continue
                    covered += 1
                    for c in range(3):
                        total[c] += colour[c]
            if covered:
                index = y * WIDTH + x
                coverage = covered / (samples * samples)
                ball = tuple(v / covered for v in total)
                pixels[index] = mix(pixels[index], ball, coverage)
    return pixels


def as_bytes(pixels):
    return bytes(max(0, min(255, int(round(c)))) for colour in pixels for c in colour)


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else "Sources/Example/Resources/bouncing-ball.gif"
    base = background()
    frames = [Image.frombytes("RGB", (WIDTH, HEIGHT), as_bytes(draw_frame(base, f))) for f in range(FRAMES)]
    # One palette for every frame, from all of them: a strip of every frame.
    strip = Image.new("RGB", (WIDTH, HEIGHT * FRAMES))
    for f, image in enumerate(frames):
        strip.paste(image, (0, HEIGHT * f))
    palette = strip.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    indexed = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in frames]
    indexed[0].save(
        output, save_all=True, append_images=indexed[1:], duration=DELAYS_MS, loop=0, disposal=1)


if __name__ == "__main__":
    main()
