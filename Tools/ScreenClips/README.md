# Screen clips

The README's animated clips: each one a small TUIkit app that plays itself in a
**real terminal window** — Ghostty, iTerm2, Terminal.app or Warp — filmed and
encoded as a looping animated WebP. One command makes them all again, so a
change to how TUIkit draws is a re-run away from the README showing it.

```sh
Tools/ScreenClips/regenerate.sh                       # every clip, each in its own terminal
Tools/ScreenClips/regenerate.sh theming controls      # just these
Tools/ScreenClips/regenerate.sh theming --terminal iterm   # → theming-iterm.webp
Tools/ScreenClips/regenerate.sh --mp4 --composite     # also MP4s, and one movie of them all
```

Output goes to `Documentation/Media/clips/` (`--out` to change it), at 1.5 pixels
per point (`--scale`): sharp on a Retina display at the size GitHub shows it. Each run
opens a new terminal window, films it for the clip's length, and closes it.
Leave the windows alone while it runs; a window in front of the filmed one does
no harm (the window itself is filmed, not the screen), but a key pressed into
it reaches the app.

Needs Screen Recording permission for the app the script runs in (System
Settings → Privacy & Security → Screen & System Audio Recording), and
`img2webp` (`brew install webp`) and, for MP4s, `ffmpeg`.

## How it works

| Piece | What it does |
|---|---|
| `Sources/ScreenClips/Scenes/` | One file per clip: the app, and its **script** — keys and cues on a clock. |
| `ScreenClips play <clip>` (`Player.swift`) | Runs the clip's app under a pseudo-terminal of its own and relays everything between it and the real terminal, untouched, so TUIkit sees the real terminal (its identity, size, colours, quirks). Types the script's keys into that stream — through TUIkit's own parser and dispatch, as typed keys go — and sends its cues (a palette change, say: something no key does) down a pipe the app reads (`ClipCues`). Drops the terminal's focus reports, so the app never goes inactive because its window is not in front. Writes `start` and `end` markers. |
| `WindowRecorder` | ScreenCaptureKit. Finds the window by its process (Ghostty: the new instance's; the others: the app's window that was not there before), films it at the display's resolution, and writes a PNG per frame, scaled with Lanczos (vImage) off the capture queue, with its presentation time. Stops at the `end` marker. |
| `encode.py` | Keeps what was on the screen between the markers, sampled at 30 fps, runs of one picture merged into one longer frame, and encodes a lossy WebP looped forever with `img2webp`, stepping the quality down until it fits the size budget (1.4 MB). Optionally an MP4 per clip and a composite movie, with ffmpeg. |
| `regenerate.sh` | Builds, stages the binaries in `~/Library/Caches/tuikit-probe/screenclips` (Ghostty may not open files under `~/Documents`), and for each clip opens the terminal, films, closes, encodes. |

The script's clock starts once the app has drawn its first frame and settled
(1.2 s after its first output), and nothing before that is kept, so every run
of a clip starts on the same picture and lands its keys at the same instants.
ScreenCaptureKit sends a frame only when the window's pixels change, so a still
screen costs one frame, however long it is held.

### Terminals

- **Ghostty** (`ghostty`, the default): a new instance (`open -na`) with every
  option on the command line and no config file read, so the look never depends
  on anyone's settings: JetBrains Mono 14 pt, the clip's size in cells, padding
  in the page's own colour, a native title bar. The clip is the window's
  `--initial-command=direct:…`, not `-e`: `-e` asks "Allow Ghostty to execute
  …?" for every new script path, and a window macOS restores runs its command
  again (that is how a clip once played twice, in two tabs). The instance is
  found by its command line, which names the run's folder, and quits when the
  clip's window closes, leaving the owner's own Ghostty alone.
- **iTerm2, Terminal.app, Warp** (`iterm`, `apple`, `warp`): a window opened
  with `open -a <app> play.command`, in the user's default profile, sized by
  `ESC[8;rows;cols t` (which iTerm2 refuses, so its window is the profile's
  size). Whether the window closes when the clip ends is the profile's choice.

## Writing a clip

Add a file to `Sources/ScreenClips/Scenes/` with a `Clip` — an id, a title,
the terminal's size in cells, the terminal to film it in, the script, and the
app to run — and list it in `clips` (`Clip.swift`). A script is `[Step]`:
`.wait(seconds)`, `.keys(bytes)` (`.tab`, `.space`, `.down`, `Step.type("text")`,
…) and `.cue(name)`, which the app's `.task { for await cue in ClipCues.stream() { … } }`
receives. End the script where it began if you can, so the loop has no seam.

`ScreenClips play <clip>` runs a clip in the terminal you are in, for a look
at it while you write it.
