#!/bin/zsh
# regenerate.sh — films the README's clips in real terminal windows and encodes them as looping animated WebPs.
#
#   Tools/ScreenClips/regenerate.sh [--terminal ghostty|iterm|apple|warp] [--out DIR] [--scale S] [--mp4]
#                                   [--composite] [--no-build] [--keep-frames] [clip ...]
#
# With no clips named, does every clip (`ScreenClips list`). Each is filmed in its own terminal (the clip says which;
# --terminal overrides it, and the file is then named <clip>-<terminal>.webp) and written to DIR, by default
# Documentation/Media/clips. --scale is output pixels per point (default 1.5; 1 = the window's size in points; the film is taken
# at the display's resolution and scaled down). --mp4 also writes an MP4 of each clip, and --composite one movie of
# them all, composite.mp4, both into the work folder (not the repo) unless --out says otherwise.
#
# What a run does, per clip: builds the package (release), stages the binaries outside ~/Documents (Ghostty may not
# open files there), opens a NEW terminal window running `ScreenClips play <clip>` — the clip's app, its script typed
# into it — films that window with WindowRecorder until the player writes its end marker, closes what it opened, and
# hands the frames to encode.py.
#
# Needs: Screen Recording permission for the app this runs in; libwebp (img2webp) and, for --mp4, ffmpeg, from
# Homebrew. Builds with $SWIFT (default: `xcrun swift`) under DEVELOPER_DIR (default: Xcode's).
set -euo pipefail

here=${0:A:h}
repo=${here:h:h}
terminal_override=""
out="$repo/Documentation/Media/clips"
scale=1.5
mp4=0
composite=0
build=1
keep=0
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
        -h|--help) sed -n '2,18p' $0; exit 0 ;;
        -*) print -u2 "regenerate.sh: unknown option $1"; exit 2 ;;
        *) clips_wanted+=$1; shift ;;
    esac
done

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
unset SDKROOT
swift_cmd=(${=SWIFT:-xcrun swift})  # xcrun honours DEVELOPER_DIR; a bare `swift` may be another toolchain
if (( build )); then
    $swift_cmd build -c release --package-path $here
fi
bin=$($swift_cmd build -c release --package-path $here --show-bin-path | grep '^/' | tail -1)  # a wrapper (slot.py) may print lines of its own

# Staged where every terminal may run it: Ghostty is refused files under ~/Documents.
probe=$HOME/Library/Caches/tuikit-probe
stage=$probe/screenclips
mkdir -p $stage/bin
rm -rf $stage/bin/*(N)
cp $bin/ScreenClips $bin/WindowRecorder $stage/bin/
for bundle in $bin/*.bundle(N); do cp -R $bundle $stage/bin/; done
player=$stage/bin/ScreenClips
recorder=$stage/bin/WindowRecorder

(( ${#clips_wanted} )) || clips_wanted=(${(f)"$($player list | cut -f1)"})
mkdir -p $out
work=$stage/runs
mkdir -p $work
movies=()

# ── Terminals ──────────────────────────────────────────────────────────────────────────────────────────────────────
# Each opener starts a window running $script and sets `pid` (the process that owns the window) and `exclude` (that
# process's windows from before, which are not the one to film). Each closer undoes what its opener did.

open_ghostty() {
    # A new instance of its own (`open -n`), so the owner's own Ghostty windows are not touched, that quits by
    # itself when the clip's window closes. Every option on the command line and no config file read, so every run
    # looks the same. The clip runs as the window's initial command, `direct:` (no shell): unlike `-e`, which asks
    # "Allow Ghostty to execute …?" for every new script path, and whose command a restored window runs again, it
    # runs once and asks nothing. The instance is found by its command line, which names this run's folder.
    open -na /Applications/Ghostty.app --args \
        --config-default-files=false \
        --font-size=14 \
        --window-width=$columns --window-height=$rows \
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
    exclude=""
}
close_ghostty() {
    for _ in {1..50}; do kill -0 $pid 2>/dev/null || return 0; sleep 0.1; done
    kill $pid 2>/dev/null || true
}

# The others are single-instance apps that may already have the owner's windows open: the new window is told from
# those by its id. They are sized by the script (ESC[8;rows;cols t), which iTerm2 refuses, so an iTerm2 window is
# the profile's size; and they keep their window open after the script ends unless the profile says otherwise.
open_shared() {  # $1: app name for `open -a`, $2: process name
    pid=$(pgrep -x $2 | head -1 || true)
    exclude=""
    if [[ -n $pid ]]; then
        exclude=$($recorder --list --pid $pid | cut -f1 | paste -sd, -)
    fi
    open -a $1 $script
    for _ in {1..100}; do
        [[ -n $pid ]] || pid=$(pgrep -x $2 | head -1 || true)
        [[ -n $pid ]] && break
        sleep 0.1
    done
}
open_iterm() { open_shared iTerm iTerm2 }
open_apple() { open_shared Terminal Terminal }
open_warp() { open_shared Warp stable }
close_iterm() { : }
close_apple() { : }
close_warp() { : }

# ── Clips ──────────────────────────────────────────────────────────────────────────────────────────────────────────
for clip in $clips_wanted; do
    eval "$($player info $clip)"   # columns rows duration terminal title
    chosen=${terminal_override:-$terminal}
    name=$clip
    [[ $chosen == $terminal ]] || name=$clip-$chosen
    run=$work/$name
    rm -rf $run
    mkdir -p $run/config
    markers=$run/markers
    script=$run/play.command
    cat > $script <<EOF
#!/bin/zsh
# One clip, as regenerate.sh plays it. A config folder of its own, so nothing the owner chose in TUIkit apps shows.
# Played once: should a terminal run this a second time (a restored window, say), that one leaves at once rather
# than writing a second set of markers.
mkdir '$run/played' 2>/dev/null || exit 0
export TUIKIT_CONFIG_DIR='$run/config'
printf '\e]0;%s\a' 'TUIkit · $title'
[[ '$chosen' == ghostty || '$chosen' == iterm ]] || printf '\e[8;%d;%dt' $rows $columns
exec '$player' play '$clip' --markers '$markers'
EOF
    chmod +x $script

    print "── $name: $title, ${columns}×${rows}, ${duration} s, in $chosen"
    open_$chosen
    rc=0
    $recorder --pid $pid --activate ${exclude:+--exclude} ${exclude:+$exclude} --out $run/frames --markers $markers \
        --scale $scale --timeout $(( ${duration%.*} + 40 )) || rc=$?
    close_$chosen
    (( rc == 0 )) || { print -u2 "regenerate.sh: filming $name failed ($rc); frames in $run"; exit 1 }

    encode=(python3 $here/encode.py clip $run/frames $markers $out/$name.webp)
    (( mp4 )) && { encode+=(--mp4 $run/$name.mp4); movies+=$run/$name.mp4 }
    $encode
    (( keep )) || rm -rf $run/frames
done

if (( composite )) && (( ${#movies} > 1 )); then
    python3 $here/encode.py composite $work/composite.mp4 $movies
fi
