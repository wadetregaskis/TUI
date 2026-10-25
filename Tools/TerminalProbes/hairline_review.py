#!/usr/bin/env python3
"""A list drawn with TUIkit's `.hairline` separators, to look at in a real terminal.

Not a measuring probe: `hairline_probe.py` asked the protocol questions and
recorded the answers (`data/*-hairline.json`). This one builds a TUIkit app
and runs it in the terminal it is started from, so a person can look at what
the framework now draws: a line a pixel or two thick on the boundary between
two list rows, taking no row (decisions A-D6L-2, the owner's option 4).

    python3 Tools/TerminalProbes/hairline_review.py            # Stress's megalist
    python3 Tools/TerminalProbes/hairline_review.py example    # the Example app
    python3 Tools/TerminalProbes/hairline_review.py --force    # TUIKIT_HAIRLINES=1
    python3 Tools/TerminalProbes/hairline_review.py --off      # TUIKIT_HAIRLINES=0

Run it from the repository root, in the terminal to be judged. Ghostty draws
the lines by default; iTerm2, kitty and WezTerm only with `--force`, because
nothing has measured them for it (iTerm2 3.7.3's pixel unit is unknown, so
its lines may end short of the row). `--off` draws the same list without
them, for comparison: the rows must be in the same places.

What to look at (each is a claim the tests make headlessly; this is the
terminal's half):

1. A thin grey line along the top of every row but the first, across the
   row's content, ending a cell short of the list's right edge.
2. No line above or below the focused (breathing) row, or a selected one.
3. Scrolling (arrows, Page Down): the lines stay on the boundaries, with no
   flicker and no line left behind where a row moved away.
4. A menu or sheet over the list (in `example`, a menu from the menu bar
   opened over a list): no line through it, and the lines back when it
   closes. Under a sheet's dimmed backdrop the lines are hidden, not dimmed
   (a prototype limitation).
5. Resize the window: every line back on its boundary after the redraw.
6. Quit (and Ctrl-Z, then `fg`): no line left on the shell's screen.
7. Where each line ends against the row's last cell. Ghostty's crop unit was
   left OPEN by the probe; TUIkit crops a run of n columns to
   n × (ws_xpixel // ws_col) pixels. Say whether it ends short, exact or past.

`example`: open the Lists page; the Styles section shows each list style,
and only `.sidebar` and `.insetGrouped` should draw none.
"""

import os
import subprocess
import sys

# Xcode's toolchain, as the repository's builds use: a bare `swift` may be another toolchain (swiftly's), and
# two compilers in one .build give a stale, mixed build.
SWIFT = ["xcrun", "swift"]
os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

TARGETS = {
    "megalist": ("Stress", {"TUIKIT_STRESS_SCENARIO": "megalist"}),
    "example": ("Example", {}),
}


def main(argv):
    target = "megalist"
    environment = dict(os.environ)
    for argument in argv:
        if argument in TARGETS:
            target = argument
        elif argument == "--force":
            environment["TUIKIT_HAIRLINES"] = "1"
        elif argument == "--off":
            environment["TUIKIT_HAIRLINES"] = "0"
        else:
            print(__doc__)
            return 2
    if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
        print("Apple Terminal prints Kitty graphics escapes; TUIkit never sends them there. Nothing to see.")
        return 1
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Run this in the terminal to be judged: it needs a TTY.")
        return 1
    product, extra = TARGETS[target]
    environment.update(extra)
    print(f"Building {product}…", flush=True)
    build = subprocess.run(SWIFT + ["build", "--product", product], env=environment)
    if build.returncode != 0:
        return build.returncode
    binary = subprocess.run(
        SWIFT + ["build", "--show-bin-path"], env=environment, capture_output=True, text=True
    ).stdout.strip()
    path = os.path.join(binary, product)
    os.execve(path, [path], environment)
    return 0  # not reached


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
