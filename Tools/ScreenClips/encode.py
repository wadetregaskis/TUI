#!/usr/bin/env python3
"""encode.py: a recorded clip's frames → a looping animated WebP, cropped by the clip's camera (and optionally an MP4).

    encode.py clip FRAMES_DIR MARKERS OUT.webp --framing FRAMING.json [--fps 30] [--quality 75] [--min-quality 70]
                                               [--budget-kb 450] [--radius 12] [--mp4 OUT.mp4]
    encode.py carousel OUT.webp TERMINAL RUN_DIR [TERMINAL RUN_DIR ...] [--mp4 OUT.mp4] [--hold 2.6] [--slide 0.5]
    encode.py composite OUT.mp4 CLIP.mp4 [CLIP.mp4 ...]

FRAMES_DIR is WindowRecorder's output: frame-NNNNN.png and frames.txt (a frame's number and presentation time, in
CLOCK_UPTIME_RAW nanoseconds, a line each). MARKERS is the player's: `start T` and `end T` on the same clock, `grid
COLUMNS ROWS`, and `calibrated T`, by when the film shows the player's calibration card (two magenta cells, see
Player.swift). FRAMING is `ScreenClips framing <clip>`: the clip's output width and its camera's moves, in cells.

The card gives the grid's place in the film and a cell's size in the film's pixels, which turns each camera shot into
a rectangle of pixels, fractional edges and all. The clip is what was on the screen from start to end, sampled on a
grid of --fps ticks (each tick shows the newest frame presented by then), each tick's picture cut out at the camera's
rectangle for that instant (moves eased in and out), scaled to the output width with Lanczos, and given rounded
corners on a transparent ground, so it sits on GitHub's light and dark pages alike. ScreenCaptureKit sends a frame only
when the window changes, so runs of one picture under one camera become one WebP frame with a longer duration.

The WebP is lossy, looped forever, at --quality, its colours converted to YUV the sharper (slower) way; if it comes out
over --budget-kb the quality is stepped down by 5, to no lower than --min-quality, and the first that fits (or the
last tried) is kept. A clip still over its budget at --min-quality is kept anyway, with a warning: below about 70,
WebP's blocks show as smears on flat colour and ghosts of the last frame in dark areas, which a terminal's flat
backgrounds make plain (2026-10-29: Animation at 45 and Navigation at 50 were sent back for it).

A carousel is one scene filmed in several terminals (RUN_DIR each, as regenerate.sh leaves it: frames/, markers,
framing.json), composited as a stack of cards: one in front, the previous and the next peeking out at its top left and
bottom right, the stack sliding one step diagonally every --hold seconds, each card named at its foot.

Needs Pillow (the crops, the corners, the cards), img2webp from libwebp, and ffmpeg for MP4s. Prints one line per
output: its path, size, frame count and length.
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit('encode.py: needs Pillow (python3 -m pip install Pillow)')

IMG2WEBP = shutil.which('img2webp') or '/opt/homebrew/bin/img2webp'
FFMPEG = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
FFPROBE = shutil.which('ffprobe') or '/opt/homebrew/bin/ffprobe'

# The names the carousel puts on its cards.
TERMINAL_NAMES = {'ghostty': 'Ghostty', 'iterm': 'iTerm2', 'apple': 'Apple Terminal', 'warp': 'Warp'}


# ── Reading a run ───────────────────────────────────────────────────────────────────────────────────────────────────

def read_markers(path):
    marks = {}
    with open(path) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) >= 2:
                marks.setdefault(parts[0], parts[1:])
    for name in ('start', 'end', 'calibrated', 'grid'):
        if name not in marks:
            sys.exit(f'encode.py: {path} has no `{name}` marker: {sorted(marks)}')
    return {
        'start': int(marks['start'][0]), 'end': int(marks['end'][0]),
        'calibrated': int(marks['calibrated'][0]),
        'grid': (int(marks['grid'][0]), int(marks['grid'][1])),
    }


def read_frames(directory):
    frames = []
    directory = os.path.abspath(directory)  # the MP4's frame list names them, and is read from elsewhere
    with open(os.path.join(directory, 'frames.txt')) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) == 2:
                frames.append((int(parts[1]), os.path.join(directory, f'frame-{int(parts[0]):05d}.png')))
    frames.sort()
    frames = [(time, path) for time, path in frames if os.path.exists(path)]
    if not frames:
        sys.exit(f'encode.py: no frames in {directory}')
    return frames


def digest(path, cache={}):
    if path not in cache:
        with open(path, 'rb') as handle:
            cache[path] = hashlib.sha1(handle.read()).hexdigest()
    return cache[path]


class Grid:
    """Where the terminal's grid is in the film, and a cell's size, in the film's pixels."""

    def __init__(self, frames, markers):
        columns, rows = markers['grid']
        before = [path for time, path in frames if time <= markers['calibrated']]
        path = before[-1] if before else frames[0][1]
        image = Image.open(path).convert('RGB')
        red, green, blue = image.split()
        magenta = ImageChops.multiply(
            ImageChops.multiply(red.point(lambda v: 255 if v > 190 else 0), green.point(lambda v: 255 if v < 90 else 0)),
            blue.point(lambda v: 255 if v > 190 else 0))
        width, height = image.size
        first = magenta.crop((0, 0, width // 2, height // 2)).getbbox()
        last = magenta.crop((width // 2, height // 2, width, height)).getbbox()
        if not first or not last:
            sys.exit(f'encode.py: no calibration card in {path} (the frame filmed before `calibrated`)')
        last = (last[0] + width // 2, last[1] + height // 2, last[2] + width // 2, last[3] + height // 2)
        self.cell_width = (last[0] - first[0]) / (columns - 3)
        self.cell_height = (last[1] - first[1]) / (rows - 3)
        self.x = first[0] - self.cell_width
        self.y = first[1] - self.cell_height
        self.columns, self.rows = columns, rows
        self.image_size = (width, height)
        painted = (first[2] - first[0], first[3] - first[1])
        if abs(painted[0] - self.cell_width) > 3 or abs(painted[1] - self.cell_height) > 3:
            print(f'encode.py: warning: the calibration cell is {painted} px, the spacing says '
                  f'{self.cell_width:.1f}×{self.cell_height:.1f}', file=sys.stderr)

    def box(self, x, y, width, height):
        """A rectangle in cells → (left, top, right, bottom) in the film's pixels, kept inside the film."""
        left = self.x + x * self.cell_width
        top = self.y + y * self.cell_height
        right = left + width * self.cell_width
        bottom = top + height * self.cell_height
        image_width, image_height = self.image_size
        dx = max(0, -left) - max(0, right - image_width)
        dy = max(0, -top) - max(0, bottom - image_height)
        return (left + dx, top + dy, right + dx, bottom + dy)


# ── The camera ──────────────────────────────────────────────────────────────────────────────────────────────────────

def ease(t):
    """Ease in and out (smootherstep): no jolt at either end of a move."""
    t = min(1.0, max(0.0, t))
    return t * t * t * (t * (t * 6 - 15) + 10)


class Camera:
    """The camera's rectangle, in cells, at any instant of the script's clock."""

    def __init__(self, framing, grid, aspect=None):
        keys = framing.get('keys') or [{'at': 0, 'shot': {'x': 0, 'y': 0, 'width': grid.columns,
                                                          'height': grid.rows, 'over': 0}}]
        first = keys[0]['shot']
        # Every shot keeps the output's proportions (height ÷ width, in pixels): the first shot's, unless the caller
        # fixes them (a carousel's cards are all one size, whatever each terminal's cell).
        self.aspect = aspect or (first['height'] * grid.cell_height) / (first['width'] * grid.cell_width)
        self.moves = []  # (start, length, rect from, rect to)
        for index, key in enumerate(keys):
            shot = key['shot']
            centre_y = shot['y'] + shot['height'] / 2
            height = shot['width'] * grid.cell_width * self.aspect / grid.cell_height
            target = (shot['x'], centre_y - height / 2, shot['width'], height)
            if index == 0:
                self.moves.append((-1e9, 0, target, target))
            else:
                self.moves.append((key['at'], shot.get('over', 0), self.at(key['at']), target))

    def at(self, time):
        rect = self.moves[0][3]
        for start, length, origin, target in self.moves:
            if time < start:
                break
            if length <= 0 or time >= start + length:
                rect = target
            else:
                p = ease((time - start) / length)
                rect = tuple(a + (b - a) * p for a, b in zip(origin, target))
        return rect


# ── The pointer ─────────────────────────────────────────────────────────────────────────────────────────────────────

class Pointer:
    """Where the drawn pointer is at any instant of the script's clock, and how far a click's ripple has spread.

    The script's mouse reports go to the app as bytes; nothing moves the machine's own pointer, and a terminal does not
    draw one. So it is drawn here, from `framing['pointer']` (`ScreenClips framing`), with the system's own arrow
    image (`WindowRecorder --cursor`): it glides into each press or `.point` from wherever it was, follows a drag
    report by report, and a press sends out a ring. Before the first event it is not drawn."""

    GLIDE = 0.45      # seconds a move into a press takes, when the press is not part of a drag
    RIPPLE = 0.4      # seconds a click's ring takes to spread and fade

    def __init__(self, events, image, hot_spot):
        self.events = sorted(events, key=lambda e: e['at'])
        self.image = image
        self.hot_spot = hot_spot

    def at(self, time):
        """((column, row) in cells from the grid's top-left, ripple progress 0–1 or None), or None if not drawn."""
        if not self.events or time < self.events[0]['at'] - self.GLIDE - 0.25:
            return None
        def centre(event):
            return (event['column'] - 0.5, event['row'] - 0.4)
        first = self.events[0]
        position = (centre(first)[0] + 5, centre(first)[1] + 3)  # comes in from below right
        previous_at = first['at'] - self.GLIDE
        for event in self.events:
            target = centre(event)
            if event['kind'] == 'drag' or event['kind'] == 'release':
                glide_start = previous_at
            else:
                glide_start = max(previous_at, event['at'] - self.GLIDE)
            if time < event['at']:
                if time <= glide_start:
                    break
                p = ease((time - glide_start) / max(1e-6, event['at'] - glide_start))
                position = tuple(a + (b - a) * p for a, b in zip(position, target))
                break
            position, previous_at = target, event['at']
        ripple = None
        for event in self.events:
            if event['kind'] == 'press' and 0 <= time - event['at'] < self.RIPPLE:
                ripple = (time - event['at']) / self.RIPPLE
        return position, ripple

    def draw(self, picture, state, grid, box):
        """Draws the pointer onto `picture`, an output frame cut from the film at `box` (film pixels)."""
        (column, row), ripple = state
        scale = picture.width / (box[2] - box[0])
        x = (grid.x + column * grid.cell_width - box[0]) * scale
        y = (grid.y + row * grid.cell_height - box[1]) * scale
        if ripple is not None:
            layer = Image.new('RGBA', picture.size, (0, 0, 0, 0))
            radius = grid.cell_width * scale * (0.6 + 1.6 * ripple)
            alpha = int(200 * (1 - ripple))
            ImageDraw.Draw(layer).ellipse((x - radius, y - radius, x + radius, y + radius),
                                          outline=(255, 255, 255, alpha), width=max(2, int(scale * 3)))
            picture.alpha_composite(layer)
        size = (max(1, round(self.image.width * scale)), max(1, round(self.image.height * scale)))
        arrow = self.image.resize(size, Image.LANCZOS)
        picture.alpha_composite(arrow, (round(x - self.hot_spot[0] * scale), round(y - self.hot_spot[1] * scale)))


def rounded_mask(size, radius, supersample=4):
    """An anti-aliased rounded rectangle, white on black, the size of an output frame."""
    width, height = size
    big = Image.new('L', (width * supersample, height * supersample), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, width * supersample - 1, height * supersample - 1), radius=radius * supersample, fill=255)
    return big.resize(size, Image.LANCZOS)


class Source:
    """The film's frames, decoded once each, the last few kept."""

    def __init__(self):
        self.cache = {}

    def image(self, path):
        if path not in self.cache:
            if len(self.cache) > 4:
                self.cache.pop(next(iter(self.cache)))
            self.cache[path] = Image.open(path).convert('RGB')
        return self.cache[path]


def shown_at(frames, start, end, fps):
    """The film's frame on the screen at each tick from start to end."""
    tick = 1e9 / fps
    ticks = int((end - start) // tick) + 1
    shown, index = [], 0
    for k in range(ticks):
        at = start + k * tick
        while index + 1 < len(frames) and frames[index + 1][0] <= at:
            index += 1
        shown.append(frames[index][1])
    return shown


def clip_sequence(frames, markers, framing, fps, radius, workdir, camera_fps=15, cursor=None):
    """[(png path, duration ms)]: the clip, cropped and cornered, runs of one picture merged.

    The camera moves at `camera_fps`, not every tick: a move changes every pixel of every frame it lasts, so it is
    the costliest thing in a clip, and an eased move at 15 steps a second still reads as a glide."""
    grid = Grid(frames, markers)
    camera = Camera(framing, grid)
    width = int(framing.get('output', 560))
    height = int(round(width * camera.aspect / 2)) * 2
    mask = rounded_mask((width, height), radius)
    start, end = markers['start'], markers['end']
    shown = shown_at(frames, start, end, fps)
    pointer = Pointer(framing['pointer'], *cursor) if cursor and framing.get('pointer') else None
    runs = []  # [key, path, rect, pointer state, first tick, last tick]
    for k, path in enumerate(shown):
        rect = tuple(round(v, 3) for v in camera.at(int(k / fps * camera_fps) / camera_fps))
        state = pointer.at(k / fps) if pointer else None
        if state:
            state = (tuple(round(v, 2) for v in state[0]), None if state[1] is None else round(state[1], 2))
        key = (digest(path), rect, state)
        if runs and runs[-1][0] == key:
            runs[-1][5] = k
        else:
            runs.append([key, path, rect, state, k, k])
    source = Source()
    total_ms = (end - start) / 1e6
    sequence = []
    for i, (_, path, rect, state, first, _) in enumerate(runs):
        box = grid.box(*rect)
        picture = source.image(path).resize((width, height), Image.LANCZOS, box=box).convert('RGBA')
        if state:
            pointer.draw(picture, state, grid, box)
        picture.putalpha(mask)
        out = os.path.join(workdir, f'out-{i:05d}.png')
        picture.save(out, compress_level=1)
        begin = round(first * 1000 / fps)
        finish = round(runs[i + 1][4] * 1000 / fps) if i + 1 < len(runs) else round(total_ms)
        sequence.append((out, max(1, finish - begin)))
    return sequence


# ── Encoding ────────────────────────────────────────────────────────────────────────────────────────────────────────

def encode_webp(sequence, out, quality):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as args:
        # File-level options, then each frame's own: its duration, lossy at this quality. Method 4, not the slowest
        # (6): on a clip of a table, 6 took 27 s to 4's 1.3 s and saved 2%. -sharp_yuv: lossy WebP keeps colour at
        # half resolution, and the usual conversion bleeds a coloured glyph into its ground; the sharp one costs
        # about 10% more bytes at the same quality (Animation at 75: 869 → 957 KB, 28.2 → 28.8 dB).
        args.write('-loop 0 -kmax 120 -sharp_yuv\n')
        for path, duration in sequence:
            args.write(f'-d {duration} -lossy -q {quality} -m 4 {path}\n')
        args.write(f'-o {out}\n')
        name = args.name
    try:
        subprocess.run([IMG2WEBP, name], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    finally:
        os.unlink(name)
    return os.path.getsize(out)


def encode_within_budget(sequence, out, quality, min_quality, budget_kb):
    while True:
        size = encode_webp(sequence, out, quality)
        if size <= budget_kb * 1024:
            return size, quality
        if quality - 5 < min_quality:
            print(f'encode.py: warning: {out} is {size / 1024:.0f} KB at quality {quality}, over its {budget_kb} KB '
                  f'budget; kept, as a lower quality shows blocks', file=sys.stderr)
            return size, quality
        quality -= 5


def encode_mp4(sequence, out, fps):
    """An H.264 MP4 of the sequence, at a constant fps, the transparent corners on a dark grey."""
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as listing:
        listing.write('ffconcat version 1.0\n')
        for path, duration in sequence:
            listing.write(f"file '{path}'\nduration {duration / 1000:.3f}\n")
        listing.write(f"file '{sequence[-1][0]}'\n")  # the concat demuxer drops the last entry's duration otherwise
        name = listing.name
    try:
        subprocess.run([
            FFMPEG, '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', name,
            '-filter_complex',
            f'color=c=0x1e1e1e:s=16x16[bg];[bg][0:v]scale2ref[bg][v];[bg][v]overlay=shortest=1:format=auto,'
            f'fps={fps},pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p',
            '-c:v', 'libx264', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', out,
        ], check=True)
    finally:
        os.unlink(name)
    return os.path.getsize(out)


def report(out, size, sequence, quality):
    length = sum(duration for _, duration in sequence) / 1000
    with Image.open(sequence[0][0]) as first:
        dimensions = f'{first.width}×{first.height}'
    print(f'{out}\t{size / 1024:.0f} KB\t{dimensions}\t{len(sequence)} frames\t{length:.2f} s\tq{quality}')


# ── Carousel ────────────────────────────────────────────────────────────────────────────────────────────────────────

def label_font(size):
    for path in ('/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc',
                 '/Library/Fonts/Arial.ttf'):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


class Card:
    """One terminal's film of the scene, cropped to the card's size, its name at its foot."""

    def __init__(self, terminal, run, card_size, aspect, fps, radius):
        frames = read_frames(os.path.join(run, 'frames'))
        markers = read_markers(os.path.join(run, 'markers'))
        with open(os.path.join(run, 'framing.json')) as handle:
            framing = json.load(handle)
        self.grid = Grid(frames, markers)
        self.camera = Camera(framing, self.grid, aspect=aspect)
        self.shown = shown_at(frames, markers['start'], markers['end'], fps)
        self.fps = fps
        self.size = card_size
        self.mask = rounded_mask(card_size, radius)
        self.source = Source()
        self.pictures = {}
        name = TERMINAL_NAMES.get(terminal, terminal)
        # The name: a dark pill, centred on the card's foot.
        self.label = Image.new('RGBA', card_size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(self.label)
        font = label_font(max(14, card_size[1] // 17))
        left, top, right, bottom = draw.textbbox((0, 0), name, font=font)
        pad_x, pad_y = font.size * 0.8, font.size * 0.35
        pill_w, pill_h = right - left + 2 * pad_x, bottom - top + 2 * pad_y
        x0 = (card_size[0] - pill_w) / 2
        y0 = card_size[1] - pill_h - font.size * 0.7
        draw.rounded_rectangle((x0, y0, x0 + pill_w, y0 + pill_h), radius=pill_h / 2, fill=(20, 20, 24, 215),
                               outline=(255, 255, 255, 60), width=1)
        draw.text((x0 + pad_x - left, y0 + pad_y - top), name, font=font, fill=(245, 245, 245, 255))

    def picture(self, time):
        """The card at `time` seconds into its film, looping."""
        k = int(time * self.fps) % len(self.shown)
        path = self.shown[k]
        rect = tuple(round(v, 3) for v in self.camera.at(k / self.fps))
        key = (path, rect)
        if key not in self.pictures:
            image = self.source.image(path).resize(self.size, Image.LANCZOS, box=self.grid.box(*rect)).convert('RGBA')
            image.alpha_composite(self.label)
            image.putalpha(ImageChops.multiply(image.getchannel('A'), self.mask))
            self.pictures[key] = image
        return self.pictures[key]


def carousel(out, pairs, mp4, hold, slide, fps, width, quality, min_quality, budget_kb, radius):
    # The canvas: the front card, with room at its top left and bottom right for the cards behind to peek out.
    with open(os.path.join(pairs[0][1], 'framing.json')) as handle:
        framing = json.load(handle)
    width = width or int(framing.get('output', 800))
    card_w = int(width * 0.74) // 2 * 2
    first = framing['keys'][0]['shot'] if framing.get('keys') else None
    # The cards' proportions: the first terminal's view of the first shot.
    grid = Grid(read_frames(os.path.join(pairs[0][1], 'frames')), read_markers(os.path.join(pairs[0][1], 'markers')))
    aspect = (first['height'] * grid.cell_height) / (first['width'] * grid.cell_width) if first else 0.6
    card_h = int(card_w * aspect) // 2 * 2
    step_x, step_y = (width - card_w) / 2 - 6, card_h * 0.13
    height = int(card_h + 2 * step_y + 24) // 2 * 2
    cards = [Card(terminal, run, (card_w, card_h), aspect, fps, radius) for terminal, run in pairs]
    count = len(cards)
    centre = ((width - card_w) / 2, (height - card_h) / 2)
    period = hold + slide
    total = period * count
    shadow_cache = {}

    def place(canvas, card_picture, slot):
        """Draws a card at a slot: 0 in front, ±1 peeking, ±2 gone; fractional in between."""
        distance = min(abs(slot), 1.0)
        scale = 1 - 0.12 * distance
        brightness = 1 - 0.5 * distance
        opacity = 1.0 if abs(slot) <= 1 else max(0.0, 2 - abs(slot))
        if opacity <= 0:
            return
        w, h = int(card_w * scale), int(card_h * scale)
        picture = card_picture.resize((w, h), Image.LANCZOS) if scale != 1 else card_picture.copy()
        if brightness < 1:
            alpha = picture.getchannel('A')
            picture = Image.eval(picture.convert('RGB'), lambda v: int(v * brightness)).convert('RGBA')
            picture.putalpha(alpha)
        if opacity < 1:
            picture.putalpha(picture.getchannel('A').point(lambda a: int(a * opacity)))
        x = centre[0] + slot * step_x + (card_w - w) / 2
        y = centre[1] + slot * step_y + (card_h - h) / 2
        # A soft shadow under each card, so the stack reads as a stack on either page colour.
        key = (w, h, round(opacity, 2))
        if key not in shadow_cache:
            pad = 16
            shadow = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
            ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 3, pad + w, pad + h + 3), radius=radius,
                                                     fill=(0, 0, 0, int(110 * opacity)))
            shadow_cache[key] = shadow.filter(ImageFilter.GaussianBlur(7))
        canvas.alpha_composite(shadow_cache[key], (int(round(x)) - 16, int(round(y)) - 16))
        canvas.alpha_composite(picture, (int(round(x)), int(round(y))))

    with tempfile.TemporaryDirectory() as workdir:
        sequence, last_digest = [], None
        ticks = int(round(total * fps))
        for k in range(ticks):
            t = k / fps
            step, phase = divmod(t, period)
            front = int(step) % count
            p = ease((phase - hold) / slide) if phase > hold else 0.0
            canvas = Image.new('RGBA', (width, height), (0, 0, 0, 0))
            slots = []
            for index, card in enumerate(cards):
                offset = (index - front) % count
                if offset > count // 2:
                    offset -= count
                if offset == count // 2 and count % 2 == 0 and p == 0:
                    continue  # the card across the stack waits, unseen, for its turn to come in
                slot = offset - p
                # The card coming to the front is drawn over the one leaving it.
                depth = 0 if (offset == 1 and p > 0) else abs(slot)
                slots.append((depth, index, slot))
            for _, index, slot in sorted(slots, reverse=True):
                # Only the card in front plays; the others hold still, on the picture they will open on (or
                # left on). Three films playing at once are three films' worth of bytes, and only one is looked at.
                moving = abs(slot) < 1
                place(canvas, cards[index].picture(t if moving else 0), slot)
            frame_digest = hashlib.sha1(canvas.tobytes()).hexdigest()
            if frame_digest == last_digest:
                sequence[-1] = (sequence[-1][0], sequence[-1][1] + 1000 / fps)
                continue
            path = os.path.join(workdir, f'card-{k:05d}.png')
            canvas.save(path, compress_level=1)
            sequence.append((path, 1000 / fps))
            last_digest = frame_digest
        sequence = [(path, max(1, int(round(duration)))) for path, duration in sequence]
        size, used = encode_within_budget(sequence, out, quality, min_quality, budget_kb)
        report(out, size, sequence, used)
        if mp4:
            size = encode_mp4(sequence, mp4, fps)
            print(f'{mp4}\t{size / 1024:.0f} KB')


# ── Composite ───────────────────────────────────────────────────────────────────────────────────────────────────────

def composite(out, clips):
    """The clips one after another, each scaled and padded to the largest's size."""
    sizes = []
    for clip in clips:
        probe = subprocess.run([FFPROBE, '-v', 'error',
                                '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0',
                                clip], check=True, capture_output=True, text=True).stdout.strip()
        width, height = probe.split(',')[:2]
        sizes.append((int(width), int(height)))
    width = max(w for w, _ in sizes) // 2 * 2
    height = max(h for _, h in sizes) // 2 * 2
    inputs, chains = [], []
    for index, clip in enumerate(clips):
        inputs += ['-i', clip]
        chains.append(f'[{index}:v]scale={width}:{height}:force_original_aspect_ratio=decrease,'
                      f'pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x1e1e1e,setsar=1,fps=30[v{index}]')
    graph = ';'.join(chains) + ';' + ''.join(f'[v{i}]' for i in range(len(clips))) + f'concat=n={len(clips)}:v=1[out]'
    subprocess.run([FFMPEG, '-v', 'error', '-y', *inputs, '-filter_complex', graph, '-map', '[out]',
                    '-c:v', 'libx264', '-crf', '20', '-preset', 'slow', '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart', out], check=True)
    print(f'{out}\t{os.path.getsize(out) / 1024:.0f} KB\t{len(clips)} clips')


def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'composite':
        if len(sys.argv) < 4:
            sys.exit(__doc__)
        composite(sys.argv[2], sys.argv[3:])
        return
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--quality', type=int, default=75)
    common.add_argument('--min-quality', type=int, default=70)
    common.add_argument('--budget-kb', type=int, default=450)
    common.add_argument('--radius', type=int, default=12, help='corner radius, output pixels')
    common.add_argument('--mp4')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    modes = parser.add_subparsers(dest='mode', required=True)
    clip = modes.add_parser('clip', parents=[common])
    clip.add_argument('frames')
    clip.add_argument('markers')
    clip.add_argument('out')
    clip.add_argument('--framing', required=True)
    clip.add_argument('--fps', type=float, default=30)
    clip.add_argument('--cursor', help='the pointer to draw where the script points: a PNG (WindowRecorder --cursor)')
    clip.add_argument('--hot-spot', default='0,0', help="the pointer image's hot spot, in its pixels: X,Y")
    deck = modes.add_parser('carousel', parents=[common])
    deck.add_argument('out')
    deck.add_argument('pairs', nargs='+', help='TERMINAL RUN_DIR, repeated')
    deck.add_argument('--hold', type=float, default=2.6)
    # A slide moves and rescales whole cards, so every frame of it is new: at 0.5 s and 15 fps, the four-terminal
    # Unicode carousel was 736 KB at quality 45; at 0.3 s and 10 fps it is 416 KB at 55 (2026-10-25).
    deck.add_argument('--slide', type=float, default=0.3)
    deck.add_argument('--fps', type=float, default=10)
    deck.add_argument('--width', type=int, default=0)
    options = parser.parse_args()

    if options.mode == 'carousel':
        if len(options.pairs) % 2:
            sys.exit('encode.py: carousel takes TERMINAL RUN_DIR pairs')
        pairs = list(zip(options.pairs[0::2], options.pairs[1::2]))
        carousel(options.out, pairs, options.mp4, options.hold, options.slide, options.fps, options.width,
                 options.quality, options.min_quality, options.budget_kb, options.radius)
        return

    with open(options.framing) as handle:
        framing = json.load(handle)
    markers = read_markers(options.markers)
    with tempfile.TemporaryDirectory() as workdir:
        cursor = None
        if options.cursor:
            hot_spot = tuple(int(v) for v in options.hot_spot.split(','))
            cursor = (Image.open(options.cursor).convert('RGBA'), hot_spot)
        sequence = clip_sequence(read_frames(options.frames), markers, framing, options.fps, options.radius, workdir,
                                 cursor=cursor)
        # A clip may ask for its own quality and budget (`Clip.quality`, `Clip.budgetKB`): photographs and blurs
        # show WebP's blocks at the default 75 where flat colour does not.
        size, quality = encode_within_budget(sequence, options.out, framing.get('quality', options.quality),
                                             options.min_quality, framing.get('budgetKB', options.budget_kb))
        report(options.out, size, sequence, quality)
        if options.mp4:
            size = encode_mp4(sequence, options.mp4, int(options.fps))
            print(f'{options.mp4}\t{size / 1024:.0f} KB')


if __name__ == '__main__':
    main()
