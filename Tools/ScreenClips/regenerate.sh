#!/bin/zsh
# regenerate.sh — films the README's clips in real terminal windows and encodes them as looping animated WebPs.
#
#   Tools/ScreenClips/regenerate.sh [--terminal ghostty|iterm|apple|warp] [--out DIR] [--scale S] [--mp4]
#                                   [--composite] [--no-build] [--keep-frames] [--encode-only] [clip ...]
#   Tools/ScreenClips/regenerate.sh --publish [--out DIR]
#
# With no clips named, does every clip (`ScreenClips list`). Each is filmed in its own terminal (the clip says which;
# --terminal overrides it, and the file is then named <clip>-<terminal>.webp) and written to DIR, by default
# Tools/ScreenClips/.build/media (git-ignored: the clips are never committed). A carousel clip is filmed once in each
# of its terminals and the films composited into one. --scale is the film's pixels per point (default 2, a Retina
# display's own); the encoder crops the clip's camera out of it and scales that to the clip's output width. --mp4 also
# writes an MP4 of each clip, and --composite one movie of them all, composite.mp4. --encode-only encodes again from
# the frames a --keep-frames run left, without filming.
#
# --publish uploads every .webp and .mp4 in DIR as assets of the GitHub release `media` (made if missing), replacing
# assets of the same name; the docs site serves them from there. It publishes: run it only when you mean to.
#
# What a run does, per clip: builds the package (release), stages the binaries outside ~/Documents (Ghostty may not
# open files there), opens a terminal window in the BACKGROUND running `ScreenClips play <clip>` — the clip's app, its
# script typed into it — films that window with WindowRecorder, behind whatever covers it, until the player writes
# its end marker, closes what it opened, and hands the frames to encode.py.
#
# Needs: Screen Recording permission for the app this runs in; libwebp (img2webp), Pillow (python3 -m pip install
# Pillow) and, for --mp4 and carousels, ffmpeg, from Homebrew. Builds with $SWIFT (default: `xcrun swift`) under
# DEVELOPER_DIR (default: Xcode's).
set -euo pipefail

here=${0:A:h}
repo=${here:h:h}
terminal_override=""
out="$here/.build/media"
scale=2
mp4=0
composite=0
build=1
keep=0
encode_only=0
publish=0
clips_wanted=()
while (( $# )); do
    case $1 in
        --terminal) terminal_override=$2; shift 2 ;;
        --out) out=${2:A}; shift 2 ;;
        --scale) scale=$2; shift 2 ;;
        --mp4) mp4=1; shift ;;
        --composite) mp4=1; composite=1; shift ;;
        --no-build) build=0; shift ;;
        --keep-frames) keep=1; shift ;;
        --encode-only) encode_only=1; build=0; keep=1; shift ;;
        --publish) publish=1; shift ;;
        -h|--help) sed -n '2,25p' $0; exit 0 ;;
        -*) print -u2 "regenerate.sh: unknown option $1"; exit 2 ;;
        *) clips_wanted+=$1; shift ;;
    esac
done

# ── Publishing ─────────────────────────────────────────────────────────────────────────────────────────────────────
# The clips live as assets of one GitHub release, `media`, not in the repository: committed, every clone would carry
# every version of every clip forever. The docs site's workflow downloads them from the release and serves them at
# <site>/media/<name>, which is where the README points.
if (( publish )); then
    files=($out/*.webp(N) $out/*.mp4(N))
    (( ${#files} )) || { print -u2 "regenerate.sh: nothing to publish in $out"; exit 1 }
    if ! gh release view media >/dev/null 2>&1; then
        gh release create media --title "README media" \
            --notes "The README's clips, made by Tools/ScreenClips/regenerate.sh and served by the docs site. Not a release of TUIkit."
    fi
    gh release upload media $files --clobber
    print "published ${#files} files to the release 'media'"
    exit 0
fi

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
unset SDKROOT
swift_cmd=(${=SWIFT:-xcrun swift})  # xcrun honours DEVELOPER_DIR; a bare `swift` may be another toolchain
if (( build )); then
    $swift_cmd build -c release --package-path $here
fi

# Staged where every terminal may run it: Ghostty is refused files under ~/Documents. So are the clips' own files
# (a picture), which the player finds beside itself.
probe=$HOME/Library/Caches/tuikit-probe
stage=$probe/screenclips
player=$stage/bin/ScreenClips
recorder=$stage/bin/WindowRecorder
if (( ! encode_only )); then
    bin=$($swift_cmd build -c release --package-path $here --show-bin-path | grep '^/' | tail -1)  # a wrapper (slot.py) may print lines of its own
    mkdir -p $stage/bin
    rm -rf $stage/bin/*(N)
    cp $bin/ScreenClips $bin/WindowRecorder $stage/bin/
    for bundle in $bin/*.bundle(N); do cp -R $bundle $stage/bin/; done
    python3 $here/make_photos.py $stage/bin/photos >/dev/null  # the photo library's pictures, painted
fi

(( ${#clips_wanted} )) || clips_wanted=(${(f)"$($player list | cut -f1)"})
mkdir -p $out
work=$stage/runs
mkdir -p $work
movies=()
# The pointer the clips draw where their scripts point: this machine's own arrow, at its screen's scale.
cursor=$stage/cursor.png
hot_spot=${(j:,:)${(z)"$($recorder --cursor $cursor)"}}

# ── Terminals ──────────────────────────────────────────────────────────────────────────────────────────────────────
# Each opener starts a window running $script, in the background, and sets `pid` (the process that owns the window)
# and `which_window` (the recorder's options for telling the window from the others that process has). Each closer undoes what
# its opener did. None of them brings anything to the front on purpose; where a terminal does (below), the recorder
# gives the front straight back to the app that had it (`--refront`).

open_ghostty() {
    # A new instance of its own (`open -n`), so the owner's own Ghostty windows are not touched, that quits by
    # itself when the clip's window closes. Every option on the command line and no config file read, so every run
    # looks the same. The clip runs as the window's initial command, `direct:` (no shell): unlike `-e`, which asks
    # "Allow Ghostty to execute …?" for every new script path, and whose command a restored window runs again, it
    # runs once and asks nothing. The instance is found by its command line, which names this run's folder.
    #
    # Opened in the background (`-g`), Ghostty 1.3 makes no window at all: it makes its first one when it is first
    # activated. So the recorder activates it (`--wake`) and at once gives the front back: the window shows in front
    # for a moment, then sits behind. Behind, but not wholly covered: Ghostty stops drawing a window it cannot see at
    # all, which would freeze the film. So it opens in the screen's corner where it shows most from behind the
    # frontmost app's windows (`--spot`, from a guess at its size: 14 pt JetBrains Mono's 8.4×17 pt cell).
    local spot=(${=$($recorder --spot $(( columns * 8.4 + 24 ))x$(( rows * 17 + 48 )))})
    [[ ${spot[3]} == 0.00 ]] && print -u2 "regenerate.sh: warning: the frontmost app covers every corner of the screen;" \
        "Ghostty will not draw a window it cannot see, so the film may freeze"
    open -g -na /Applications/Ghostty.app --args \
        --config-default-files=false \
        --font-size=14 \
        --window-width=$columns --window-height=$rows \
        --window-position-x=${spot[1]} --window-position-y=${spot[2]} \
        --window-padding-x=12 --window-padding-y=10 --window-padding-color=extend \
        --background=#1e1e1e --foreground=#d4d4d4 \
        --title="TUIkit · $title" \
        --macos-titlebar-style=native \
        --window-save-state=never --confirm-close-surface=false --quit-after-last-window-closed=true \
        --shell-integration=none --cursor-style-blink=false --resize-overlay=never \
        --working-directory=$run \
        --initial-command=direct:$script
    pid=""
    for _ in {1..100}; do
        pid=$(pgrep -f -- "--working-directory=$run" | head -1 || true)
        [[ -n $pid ]] && break
        sleep 0.1
    done
    [[ -n $pid ]] || { print -u2 "regenerate.sh: no new Ghostty instance started"; return 1 }
    which_window=(--wake)
}
close_ghostty() {
    for _ in {1..50}; do kill -0 $pid 2>/dev/null || return 0; sleep 0.1; done
    kill $pid 2>/dev/null || true
}

# The others are single-instance apps that may already have the owner's windows open. The clip's window is the one
# whose title the script set (`TUIkit · <title>`), and not one that was there before.
#
#  - Terminal.app opens a new window in the background, sized by the script (ESC[8;rows;cols t). Its default
#    profile keeps the window open once the script ends ("[Process completed]"), and with Apple Events refused there
#    is no closing it from here: it stays, behind, for the owner to close.
#  - iTerm2 opens a new window — or, with a window open already, a new tab in it (2026-10-25) — but brings itself to
#    the front (`-g` or not), and refuses the resize (its profile's
#    "Disable session-initiated window resizing"), so the window is the profile's size. It closes the window itself
#    when the script ends.
#  - Warp brings itself to the front and opens the script as a new TAB of the window it already has, not a window of
#    its own. The script must not resize it (that would be the owner's window), so the clip plays at that window's
#    size. The tab's shell is left behind when the script ends, and is ended here, which closes the tab.
open_shared() {  # $1: app name for `open -a`, $2: process name
    pid=$(pgrep -x $2 | head -1 || true)
    local before=""
    [[ -n $pid ]] && before=$($recorder --list --pid $pid | cut -f1 | paste -sd, -)
    open -g -a $1 $script
    for _ in {1..100}; do
        [[ -n $pid ]] || pid=$(pgrep -x $2 | head -1 || true)
        [[ -n $pid ]] && break
        sleep 0.1
    done
    which_window=(--title "TUIkit · $title|$run/play.command|${run:t}/play.command")
    # Warp, and iTerm2 when it already has a window, open the script as a tab of a window they had: that window is
    # filmed, found by the title the script sets, so it must not be excluded.
    [[ $2 == stable || $2 == iTerm2 || -z $before ]] || which_window+=(--exclude $before)
}
open_iterm() { open_shared iTerm iTerm2 }
open_apple() { open_shared Terminal Terminal }
open_warp() { open_shared Warp stable }
close_iterm() { : }
close_apple() { : }
close_warp() {
    # The tab's shell, whose working directory is the run's folder.
    local shell
    for shell in $(pgrep -P $pid; for p in $(pgrep -x stable); do pgrep -P $p; done); do
        if lsof -a -p $shell -d cwd -Fn 2>/dev/null | grep -qx "n$run"; then kill -HUP $shell 2>/dev/null || true; fi
    done
}

# Films one clip in one terminal: $clip, $chosen, $name set; leaves $run/frames, $run/markers, $run/framing.json.
film() {
    eval "$($player info $clip)"   # columns rows duration terminal title output carousel
    run=$work/$name
    rm -rf $run
    mkdir -p $run/config
    markers=$run/markers
    script=$run/play.command
    $player framing $clip > $run/framing.json
    local resize=1
    [[ $chosen == ghostty || $chosen == iterm || $chosen == warp ]] && resize=0
    cat > $script <<EOF
#!/bin/zsh
# One clip, as regenerate.sh plays it. A config folder of its own, so nothing the owner chose in TUIkit apps shows.
# Played once: should a terminal run this a second time (a restored window, say), that one leaves at once rather
# than writing a second set of markers.
cd '$run'
mkdir '$run/played' 2>/dev/null || exit 0
export TUIKIT_CONFIG_DIR='$run/config'
printf '\e]0;%s\a' 'TUIkit · $title'
(( $resize )) && printf '\e[8;%d;%dt' $rows $columns
exec '$player' play '$clip' --markers '$markers'
EOF
    chmod +x $script

    print "── $name: $title, ${columns}×${rows}, ${duration} s, in $chosen"
    local front=$($recorder --front)
    open_$chosen
    rc=0
    $recorder --pid $pid $which_window --refront $front --out $run/frames --markers $markers \
        --scale $scale --timeout $(( ${duration%.*} + 40 )) || rc=$?
    close_$chosen
    (( rc == 0 )) || { print -u2 "regenerate.sh: filming $name failed ($rc); frames in $run"; exit 1 }
}

# ── Clips ──────────────────────────────────────────────────────────────────────────────────────────────────────────
for clip in $clips_wanted; do
    eval "$($player info $clip)"
    if [[ -n $carousel && -z $terminal_override ]]; then
        # The same scene in each terminal, composited into one: a card per terminal, named.
        cards=()
        for chosen in ${=carousel}; do
            name=$clip-$chosen
            (( encode_only )) || film
            cards+=($chosen $work/$name)
        done
        encode=(python3 $here/encode.py carousel $out/$clip.webp $cards)
        (( mp4 )) && { encode+=(--mp4 $work/$clip.mp4); movies+=$work/$clip.mp4 }
        $encode
        (( keep )) || for _ dir in $cards; do rm -rf $dir/frames; done
        continue
    fi
    chosen=${terminal_override:-$terminal}
    name=$clip
    [[ $chosen == $terminal ]] || name=$clip-$chosen
    (( encode_only )) || film
    run=$work/$name
    encode=(python3 $here/encode.py clip $run/frames $run/markers $out/$name.webp --framing $run/framing.json
            --cursor $cursor --hot-spot $hot_spot)
    (( mp4 )) && { encode+=(--mp4 $work/$name.mp4); movies+=$work/$name.mp4 }
    $encode
    (( keep )) || rm -rf $run/frames
done

if (( composite )) && (( ${#movies} > 1 )); then
    python3 $here/encode.py composite $work/composite.mp4 $movies
fi
