#!/usr/bin/env python3
"""encode.py: a recorded clip's frames → a looping animated WebP (and optionally an MP4).

    encode.py clip FRAMES_DIR MARKERS OUT.webp [--fps 30] [--quality 80] [--min-quality 50]
                                               [--budget-kb 1400] [--mp4 OUT.mp4]
    encode.py composite OUT.mp4 CLIP.mp4 [CLIP.mp4 ...]

FRAMES_DIR is WindowRecorder's output: frame-NNNNN.png and frames.txt (a frame's number and presentation time, in
CLOCK_UPTIME_RAW nanoseconds, a line each). MARKERS is the player's: `start T` and `end T` on the same clock. The clip
is what was on the screen from start to end. ScreenCaptureKit sends a frame only when the window changes, so the
frames are sampled on a grid of --fps ticks (each tick shows the newest frame presented by then) and runs of one
picture become one WebP frame with a longer duration, rather than the same picture over and over.

The WebP is lossy, looped forever, at --quality; if it comes out over --budget-kb the quality is stepped down, by 10,
to no lower than --min-quality, and the smallest that fits (or the last tried) is kept. img2webp, from libwebp, does
the encoding; ffmpeg the MP4s.

Standard library only. Prints one line per output: its path, size, frame count and length.
"""
import argparse, hashlib, os, shutil, subprocess, sys, tempfile

IMG2WEBP = shutil.which('img2webp') or '/opt/homebrew/bin/img2webp'
FFMPEG = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
FFPROBE = shutil.which('ffprobe') or '/opt/homebrew/bin/ffprobe'


def read_markers(path):
    marks = {}
    with open(path) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) == 2:
                marks.setdefault(parts[0], int(parts[1]))
    if 'start' not in marks or 'end' not in marks:
        sys.exit(f'encode.py: {path} lacks a start or an end marker: {marks}')
    return marks['start'], marks['end']


def read_frames(directory):
    frames = []
    directory = os.path.abspath(directory)  # the MP4's frame list names them, and is read from elsewhere
    with open(os.path.join(directory, 'frames.txt')) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) == 2:
                frames.append((int(parts[1]), os.path.join(directory, f'frame-{int(parts[0]):05d}.png')))
    frames.sort()
    return [(time, path) for time, path in frames if os.path.exists(path)]


def digest(path, cache={}):
    if path not in cache:
        with open(path, 'rb') as handle:
            cache[path] = hashlib.sha1(handle.read()).hexdigest()
    return cache[path]


def timeline(frames, start, end, fps):
    """[(path, duration_ms)]: the picture on the screen at each tick from start to end, runs merged."""
    if not frames:
        sys.exit('encode.py: no frames')
    tick = 1e9 / fps
    ticks = int((end - start) // tick) + 1
    shown, index = [], 0
    for k in range(ticks):
        at = start + k * tick
        while index + 1 < len(frames) and frames[index + 1][0] <= at:
            index += 1
        shown.append(frames[index][1])
    runs = []  # [path, first tick, last tick]
    for k, path in enumerate(shown):
        if runs and digest(runs[-1][0]) == digest(path):
            runs[-1][2] = k
        else:
            runs.append([path, k, k])
    total_ms = (end - start) / 1e6
    out = []
    for i, (path, first, _) in enumerate(runs):
        begin = round(first * 1000 / fps)
        finish = round(runs[i + 1][1] * 1000 / fps) if i + 1 < len(runs) else round(total_ms)
        out.append((path, max(1, finish - begin)))
    return out


def encode_webp(sequence, out, quality):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as args:
        # File-level options, then each frame's own: its duration, lossy at this quality, the slowest method.
        args.write('-loop 0 -kmax 60\n')
        for path, duration in sequence:
            args.write(f'-d {duration} -lossy -q {quality} -m 6 {path}\n')
        args.write(f'-o {out}\n')
        name = args.name
    try:
        subprocess.run([IMG2WEBP, name], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    finally:
        os.unlink(name)
    return os.path.getsize(out)


def encode_mp4(sequence, out, fps):
    """An H.264 MP4 of the sequence, at a constant fps, the window's transparent corners on a dark grey."""
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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('mode', choices=['clip'])
    parser.add_argument('frames')
    parser.add_argument('markers')
    parser.add_argument('out')
    parser.add_argument('--fps', type=float, default=30)
    parser.add_argument('--quality', type=int, default=80)
    parser.add_argument('--min-quality', type=int, default=50)
    parser.add_argument('--budget-kb', type=int, default=1400)
    parser.add_argument('--mp4')
    options = parser.parse_args()

    start, end = read_markers(options.markers)
    sequence = timeline(read_frames(options.frames), start, end, options.fps)
    length = sum(duration for _, duration in sequence) / 1000
    quality = options.quality
    while True:
        size = encode_webp(sequence, options.out, quality)
        if size <= options.budget_kb * 1024 or quality - 10 < options.min_quality:
            break
        quality -= 10
    print(f'{options.out}\t{size / 1024:.0f} KB\t{len(sequence)} frames\t{length:.2f} s\tq{quality}')
    if options.mp4:
        size = encode_mp4(sequence, options.mp4, int(options.fps))
        print(f'{options.mp4}\t{size / 1024:.0f} KB')


if __name__ == '__main__':
    main()
