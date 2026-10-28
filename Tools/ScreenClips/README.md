# Screen clips

The README's animated clips: each one a TUI app that plays itself in a
**real terminal window** — Ghostty, iTerm2, Terminal.app or Warp — filmed,
cropped to a small frame of it, and encoded as a looping animated WebP. One
command makes them all again, so a change to how TUI draws is a re-run
away from the README showing it.

```sh
Tools/ScreenClips/regenerate.sh                       # every clip, each in its own terminal
Tools/ScreenClips/regenerate.sh theming controls      # just these
Tools/ScreenClips/regenerate.sh theming --terminal iterm   # → theming-iterm.webp
Tools/ScreenClips/regenerate.sh --mp4 --composite     # also MP4s, and one movie of them all
Tools/ScreenClips/regenerate.sh --keep-frames tables  # keep the film, then…
Tools/ScreenClips/regenerate.sh --encode-only tables  # …re-crop and re-encode it without filming again
Tools/ScreenClips/regenerate.sh --publish             # upload them to the `media` release (see Publishing)
```

Output goes to `Tools/ScreenClips/.build/media/` (`--out` to change it), which
git ignores: the clips are **never committed** — every version of every clip
would be in every clone forever. They are published as release assets instead.

Each run opens a terminal window **in the background**, films it for the
clip's length, and closes it. Leave the windows alone while it runs: a window
in front of the filmed one does no harm (the window itself is filmed, not the
screen), but a key pressed into it reaches the app. See [Terminals](#terminals)
for what each terminal does when opened, and why a Ghostty window shows in
front for a moment.

Needs Screen Recording permission for the app the script runs in (System
Settings → Privacy & Security → Screen & System Audio Recording), an unlocked
screen (nothing is drawn while it is locked), `img2webp` (`brew install webp`),
Pillow (`python3 -m pip install Pillow`) and, for MP4s, `ffmpeg`.

## What a clip looks like

The README shows them small: a three-column grid of tiles about 270 CSS pixels
wide (`output: 560`, for Retina screens), flagship rows of about 400 (`output:
800`), and the hero, code beside its result. So a clip is not a tiny app made
to fit a thumbnail: it is a **believable full-size app** — toolbar, sidebar,
real-looking data, at the normal font size in a normal-size window — and the
clip is a small frame of it, cut by a **camera**:

- **Every clip is 16:10**: 800 × 500 for a flagship row, 560 × 350 for a
  tile (the hero, code beside its result, has its own shape). In Ghostty's
  14 pt JetBrains Mono that is about 3.48 columns a row, as the films measure
  it: a camera of 62 × 18, 87 × 25, 112 × 32. A clip whose content is wider
  than that is recomposed taller, not filmed short — a row of mismatched
  heights looks unfinished.
- The camera is a rectangle of the terminal's grid, in cells. Its left and
  right edges may be fractional and cut through a glyph, and borders and
  repeating rows may run off the top and bottom, so the app's chrome peeks in
  at the edges: there is a bigger app behind the mask. A line of text is never
  cut in half across (see Framing, under Writing a clip).
- It can move — pan, or zoom — easing from one shot to the next, to follow the
  action (a card dragged across a board).
- The macOS title bar is left out (it is the terminal's chrome, not the app's).
- The corners are rounded, on a transparent ground, so the tiles sit as well
  on GitHub's light pages as on its dark ones.
- Something always moves: a clip with nothing happening reads as a still.

Keep each WebP well under 1 MB; 100–400 KB is the aim. The encoder steps its
quality down to fit `--budget-kb` (450). A clip of photographs or blurs sets its
own `quality` (and `budgetKB`): at the default 75 WebP draws blocks across a
smooth gradient that flat colour never shows. A camera move changes every pixel of
every frame it lasts, so moves cost more than anything else in a clip: keep
them short and few.

## How it works

| Piece | What it does |
|---|---|
| `Sources/ScreenClips/Scenes/` | One file per clip: the app, and its **script** — keys, cues and camera shots on a clock. |
| `ScreenClips play <clip>` (`Player.swift`) | Draws a calibration card (below), then runs the clip's app under a pseudo-terminal of its own and relays everything between it and the real terminal, untouched, so TUI sees the real terminal (its identity, size, colours, quirks). Types the script's keys into that stream — through TUI's own parser and dispatch, as typed keys go (mouse reports too) — and sends its cues (a palette change, say: something no key does) down a pipe the app reads (`ClipCues`). Drops the terminal's focus reports, so the app never goes inactive because its window is not in front. Writes `start` and `end` markers. |
| `WindowRecorder` | ScreenCaptureKit. Finds the window by its process (Ghostty: the new instance's; the others: the window titled for the clip), films it at the display's resolution, and writes a PNG per frame, with its presentation time. Stops at the `end` marker. Also gives the front back to the app that had it (`--refront`), and finds the screen corner where a window shows most from behind it (`--spot`). |
| `encode.py` | Finds the grid in the film from the calibration card, keeps what was on the screen between the markers, sampled at 30 fps, cuts each frame at the camera's rectangle for that instant, scales it to the clip's output width (Lanczos), draws the pointer (below), rounds its corners, merges runs of one picture into one longer frame, and encodes a lossy WebP looped forever with `img2webp`. Also composites carousels, and MP4s with ffmpeg. |
| `Photos/` | The photographs the photo library and the image viewers show: the owner's own, from [their Flickr](https://www.flickr.com/photos/wadetregaskis/), 720 pixels on the long side, WebP at quality 72 (617 KB for all 17). Staged beside the player. Clips run on macOS only, whose decoder reads WebP; the Example's demo picture, which Linux decodes too, is a JPEG. |
| `regenerate.sh` | Builds, stages the binaries in `~/Library/Caches/tuikit-probe/screenclips` (Ghostty may not open files under `~/Documents`; `SCREENCLIPS_STAGE` names another stage, which two checkouts filming at once each need, or each films the other's build), and for each clip opens the terminal, films, closes, encodes. Publishes with `--publish`. |

**The calibration card.** Before the app starts, the player clears the screen
and paints two cells magenta: the second cell of the second row, and the
second-last of the second-last row (not the corners, whose colour a terminal
may extend into its padding). It holds them until the recorder says it is
filming, and notes the instant and the grid's size in cells. The distance
between the two cells is a cell's size in the film's pixels, and the first cell
less one is where the grid starts — whatever the terminal, font, padding,
title bar or display scale — which is what lets a camera be written in cells.

**The pointer.** A clip's mouse reports go to the app as bytes: nothing moves
the machine's own pointer, and a terminal does not draw one. So the encoder
draws it, where the script points: `WindowRecorder --cursor` saves this
machine's own arrow (at its screen's scale, with its hot spot) once a run, and
`ScreenClips framing` lists every mouse report and `.point` on the script's
clock. The pointer glides into each press from wherever it was, follows a drag
report by report, and a press sends out a fading ring. Filmed on another
system, the pointer is that system's.

The script's clock starts once the app has drawn its first frame and settled
(1.2 s after its first output), and nothing before that is kept, so every run
of a clip starts on the same picture and lands its keys at the same instants.
ScreenCaptureKit sends a frame only when the window's pixels change, so a still
screen costs one frame, however long it is held.

### Terminals

No terminal is brought to the front on purpose, but not every terminal can be
opened without it, and a covered window is not always drawn:

- **Ghostty** (`ghostty`, the default): a new instance (`open -g -n`) with
  every option on the command line and no config file read, so the look never
  depends on anyone's settings: JetBrains Mono 14 pt, the clip's size in cells
  (Ghostty rounds it up a cell or two), padding in the page's own colour. The
  clip is the window's `--initial-command=direct:…`, not `-e`: `-e` asks
  "Allow Ghostty to execute …?" for every new script path, and a window macOS
  restores runs its command again. The instance quits when the clip's window
  closes, leaving the owner's own Ghostty alone.
  - Opened in the background, Ghostty 1.3 makes **no window at all** until it
    is first activated. So the recorder activates it (`--wake`) and gives the
    front straight back (`--refront`): the window shows in front for a moment,
    then sits behind.
  - Ghostty **stops drawing a window that is wholly covered**, and the film
    freezes. So the window opens in the screen corner where it shows most from
    behind the frontmost app's windows (`--spot`); a sliver showing is enough.
    If the frontmost app covers every corner, regenerate.sh warns, and the
    clip must be filmed again with some of the screen free.
- **Terminal.app** (`apple`): a new window, in the background, sized by the
  script (`ESC[8;rows;cols t`), in the default profile. It draws while covered.
  Its default profile keeps the window open when the script ends ("[Process
  completed]"), and with Apple Events refused there is no closing it from
  here: it stays, behind, to be closed by hand.
- **iTerm2** (`iterm`): brings itself to the front (`-g` or not) and opens the
  script as a new **tab** of the window it already has; the recorder gives the
  front back. It refuses the resize (the profile's "Disable session-initiated
  window resizing"), so the clip plays at that window's size. It closes the
  tab itself when the script ends.
- **Warp** (`warp`): brings itself to the front and opens the script as a new
  tab of its existing window, which the script must not resize (it is the
  owner's), so the clip plays at that window's size. The tab's shell is left
  when the script ends; regenerate.sh ends it, which closes the tab.

Since iTerm2 and Warp films are of a window someone already uses, at its size,
write clips for them to need no more than 80×24 and to draw from the top left.

## Writing a clip

Add a file to `Sources/ScreenClips/Scenes/` with a `Clip` — an id, a title,
the terminal's size in cells, the terminal to film it in, the output width,
the script, and the app to run — and list it in `clips` (`Clip.swift`). A
script is `[Step]`:

- `.wait(seconds)`;
- `.keys(bytes)` — `.tab`, `.space`, `.down`, `.shiftLeft`, `.optionRight`,
  `.f10`, `Step.control("z")`, `Step.type("text")`, `Step.click(column, row)`,
  `Step.doubleClick(column, row)`, `Step.drag(from:to:option:)` (SGR mouse
  reports, 1-based cells; `option` makes it an Option-drag), …;
- `.point(column:row:)`, which moves the drawn pointer without a press — to
  show where attention goes before a key acts there;
- `.cue(name)`, which the app's `.task { for await cue in ClipCues.stream() { … } }`
  receives;
- `.camera(Shot(x:y:width:height:over:))`, a shot in cells, eased over `over`
  seconds from that instant. Start the script with one; every later shot keeps
  the first one's proportions (only its centre and width are taken).

In a `List` or `Table`, an arrow moves the cursor and Space selects. End the
script where it began if you can, so the loop has no seam.

**Framing.** The top and bottom edges of a shot fall between rows: a line of
text cut in half reads as a mistake. What may run out of the frame is a border,
or something that repeats — a list's rows, a grid of pictures — which reads as
more of the same beyond it. The left and right edges may cut through text.

`ScreenClips play <clip>` runs a clip in the terminal you are in, for a look at
it while you write it. (With `--markers`, as regenerate.sh plays it, it first
shows the calibration card and waits up to 20 s for a recorder.)

A **carousel** clip (`carousel: ["ghostty", "iterm", "apple", "warp"]`) is
filmed once in each terminal and composited by `encode.py carousel`: the cards
stacked diagonally, one in front and the ones before and after it peeking out
at its top left and bottom right, the stack sliding a step every few seconds,
each card named at its foot. The cards are composited with Pillow and encoded
with img2webp (and ffmpeg for `--mp4`); Homebrew's ffmpeg has no `drawtext`,
and a stack whose order changes mid-slide is simpler drawn than filtered.

## Publishing

The clips live as assets of one GitHub release, `media`, which is not a release
of TUI. `regenerate.sh --publish` uploads every `.webp` and `.mp4` in the
output folder to it (`gh release upload media … --clobber`, replacing assets of
the same name), creating the release first if there is none. The docs site's
workflow downloads the assets and serves them at `<site>/media/<name>`, which
is where the README points. Publishing is public: run it only when you mean to.
