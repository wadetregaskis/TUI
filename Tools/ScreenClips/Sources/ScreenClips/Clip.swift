//  🖥️ TUI — A Terminal UI framework for Swift
//  Clip.swift
//
//  What a clip is: a TUI app, and the script the player plays against it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// One step of a clip's script, played by the player in order.
///
/// A script is a list of moves on one clock — the player's — that starts when
/// the app has drawn its first frame and settled, so the same script lands at
/// the same instants on every run. Keys are bytes typed into the app's
/// terminal, read by TUI's own parser and dispatched as a keypress is; a cue
/// is a change only the app itself can make (a palette, a value moving), sent
/// to it over a pipe of its own, so no key is spent on it and nothing on the
/// screen says it happened.
enum Step {
    /// Waits this many seconds.
    case wait(Double)
    /// Types these bytes into the app's terminal.
    case keys(String)
    /// Hands the app this cue, which its ``ClipCues`` stream delivers.
    case cue(String)
    /// Moves the camera to this shot, easing over the shot's `over` seconds
    /// from this instant. The player ignores it (it is the encoder's), so it
    /// takes no time on the script's clock.
    case camera(Shot)
    /// Moves the drawn pointer to this cell (1-based) without a press — to
    /// show where attention goes before a key acts there. The player ignores
    /// it, as it does a shot: only the encoder draws the pointer.
    case point(column: Int, row: Int)

    /// Tab: the next focus stop.
    static let tab = Self.keys("\t")
    /// Shift+Tab: the previous focus stop.
    static let backTab = Self.keys("\u{1B}[Z")
    /// Space: presses the focused button, flips the focused toggle.
    static let space = Self.keys(" ")
    /// Return.
    static let enter = Self.keys("\r")
    /// Escape.
    static let escape = Self.keys("\u{1B}")
    /// The arrow keys.
    static let up = Self.keys("\u{1B}[A")
    static let down = Self.keys("\u{1B}[B")
    static let right = Self.keys("\u{1B}[C")
    static let left = Self.keys("\u{1B}[D")

    /// Shift with an arrow: extends a text selection; steps a slider five.
    static let shiftRight = Self.keys("\u{1B}[1;2C")
    static let shiftLeft = Self.keys("\u{1B}[1;2D")
    static let shiftDown = Self.keys("\u{1B}[1;2B")
    /// Option with left or right: a word at a time, in text.
    static let optionRight = Self.keys("\u{1B}[1;3C")
    static let optionLeft = Self.keys("\u{1B}[1;3D")
    /// Option with an arrow: moves the focused row of a reorderable list.
    static let optionDown = Self.keys("\u{1B}[1;3B")
    static let optionUp = Self.keys("\u{1B}[1;3A")
    /// Page Down, Page Up, Home, End.
    static let pageDown = Self.keys("\u{1B}[6~")
    static let pageUp = Self.keys("\u{1B}[5~")
    static let home = Self.keys("\u{1B}[H")
    static let end = Self.keys("\u{1B}[F")
    /// F10 opens the menu bar's first menu; Shift+F10 a focused view's context menu.
    static let f10 = Self.keys("\u{1B}[21~")
    static let shiftF10 = Self.keys("\u{1B}[21;2~")

    /// Control with a letter (`control("f")` is Ctrl-F).
    static func control(_ letter: Character) -> Self {
        let code = letter.asciiValue.map { $0 & 0x1F } ?? 0
        return .keys(String(UnicodeScalar(code)))
    }

    /// A mouse report, as a terminal sends one in SGR mode (1006): `button`
    /// 0 is the left button, +32 while it moves; `column` and `row` are
    /// 1-based cells. The pointer itself is not filmed — a terminal does not
    /// draw it — so what shows is what the app does with the press.
    static func mouse(_ button: Int, _ column: Int, _ row: Int, release: Bool = false) -> Self {
        .keys("\u{1B}[<\(button);\(column);\(row)\(release ? "m" : "M")")
    }

    /// A left click on a cell.
    static func click(_ column: Int, _ row: Int) -> [Self] {
        [mouse(0, column, row), .wait(0.08), mouse(0, column, row, release: true)]
    }

    /// A double click on a cell: a word selected, in a text view.
    static func doubleClick(_ column: Int, _ row: Int) -> [Self] {
        click(column, row) + [.wait(0.08)] + click(column, row)
    }

    /// A left-button drag from one cell to another, a cell of motion every
    /// `interval` seconds, as a hand moves a mouse. With `option`, the report
    /// carries the Meta flag (+8), as a terminal sends an Option-drag: a
    /// rectangular selection in a text editor.
    static func drag(
        from start: (Int, Int), to end: (Int, Int), interval: Double = 0.03, option: Bool = false
    ) -> [Self] {
        let flags = option ? 8 : 0
        var steps: [Self] = [mouse(flags, start.0, start.1), .wait(0.15)]
        let count = max(abs(end.0 - start.0), abs(end.1 - start.1))
        for index in 1...max(1, count) {
            let fraction = Double(index) / Double(max(1, count))
            let column = start.0 + Int((Double(end.0 - start.0) * fraction).rounded())
            let row = start.1 + Int((Double(end.1 - start.1) * fraction).rounded())
            steps += [mouse(32 + flags, column, row), .wait(interval)]
        }
        steps += [.wait(0.2), mouse(flags, end.0, end.1, release: true)]
        return steps
    }

    /// Types `text` a character at a time, `interval` seconds apart, as a
    /// person would: one frame per keystroke, not the whole word at once.
    static func type(_ text: String, interval: Double = 0.09) -> [Self] {
        text.flatMap { [Self.keys(String($0)), .wait(interval)] }
    }

    /// `step`, `count` times, `interval` seconds apart.
    static func `repeat`(_ step: Self, _ count: Int, interval: Double) -> [Self] {
        (0..<count).flatMap { _ in [step, .wait(interval)] }
    }
}

/// What the camera frames: a rectangle of the terminal's grid, in cells. The
/// left and right edges may be fractional and cut through a glyph; the top and
/// bottom fall between rows, unless the row cut is a border or a repeating one
/// (README, Framing): a line of text cut in half across reads as a mistake.
///
/// The encoder crops each frame of the film to the camera's rectangle and
/// scales it to the clip's output width. Every shot after the first keeps the
/// first one's proportions — the output is one size — so a later shot's height
/// is worked out from its width, and only its centre and width are taken.
struct Shot: Encodable {
    /// The left and top edges, in cells from the grid's top-left corner.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// How long the move to this shot takes, eased in and out. 0 is a cut.
    var over: Double = 0
}

/// A move of the drawn pointer: `press`, `drag`, `release` or `move` (no
/// button), at a 1-based cell, at an instant on the script's clock.
struct PointerEvent: Encodable {
    let at: Double
    let column: Int
    let row: Int
    let kind: String
}

/// A clip: an app that draws the capability, and the script that shows it off.
struct Clip {
    /// The name the clip is run and saved by (`theming` → `theming.webp`).
    let id: String
    /// What the clip shows, for `ScreenClips list` and the window's title.
    let title: String
    /// The terminal's size in cells. The recorder opens the window at this size.
    let columns: Int
    let rows: Int
    /// The terminal it is filmed in unless regenerate.sh is told otherwise:
    /// `ghostty`, `iterm`, `apple` or `warp`.
    var terminal = "ghostty"
    /// For a clip about the terminals themselves: filmed once in each of
    /// these, and the films composited into one carousel, a card each.
    var carousel: [String] = []
    /// The output's width in pixels: about 560 for a tile in the README's
    /// three-column grid, about 800 for a flagship row (twice the CSS size, for
    /// Retina screens). The height follows from the first shot's proportions.
    var output = 560
    /// The script, played once the app has settled. Its first step should be a
    /// `.camera` shot: without one the camera frames the whole grid.
    let script: [Step]
    /// A real app to film instead of a scene of this package: a program staged
    /// beside the player (regenerate.sh stages the Example) and its arguments.
    /// The script's keys drive it as they drive a scene; it has no cues.
    var command: [String]?
    /// Variables set for `command` (`TUIKIT_GRAPHICS=0`, say).
    var environment: [String: String] = [:]
    /// Runs the app: called in the child the player starts under its own
    /// pseudo-terminal, and does not return until the app quits. Unused for a
    /// clip with a `command`.
    var run: @MainActor () async -> Void = {}

    /// How long the script runs, waits included.
    var duration: Double {
        script.reduce(0) { total, step in
            if case .wait(let seconds) = step { total + seconds } else { total }
        }
    }

    /// The camera's moves on the script's clock: each shot and the instant its
    /// move starts, for the encoder.
    var cameraKeys: [(at: Double, shot: Shot)] {
        var clock = 0.0
        var keys: [(at: Double, shot: Shot)] = []
        for step in script {
            switch step {
            case .wait(let seconds): clock += seconds
            case .camera(let shot): keys.append((clock, shot))
            case .keys, .cue, .point: break
            }
        }
        return keys
    }

    /// Where the pointer is sent, on the script's clock, for the encoder to
    /// draw: every SGR mouse report the script types (a press, a motion, a
    /// release), and every `.point`. Cells are 1-based, as the reports count.
    var pointerEvents: [PointerEvent] {
        var clock = 0.0
        var events: [PointerEvent] = []
        for step in script {
            switch step {
            case .wait(let seconds): clock += seconds
            case .point(let column, let row): events.append(PointerEvent(at: clock, column: column, row: row, kind: "move"))
            case .keys(let bytes):
                guard bytes.hasPrefix("\u{1B}[<"), let last = bytes.last, last == "M" || last == "m" else { continue }
                let fields = bytes.dropFirst(3).dropLast().split(separator: ";").compactMap { Int($0) }
                guard fields.count == 3 else { continue }
                let kind = last == "m" ? "release" : fields[0] & 32 != 0 ? "drag" : "press"
                events.append(PointerEvent(at: clock, column: fields[1], row: fields[2], kind: kind))
            case .camera, .cue: break
            }
        }
        return events
    }

    /// What the encoder needs to know about this clip, as JSON.
    var framingJSON: String {
        struct Key: Encodable { let at: Double; let shot: Shot }
        struct Framing: Encodable {
            let columns: Int
            let rows: Int
            let output: Int
            let keys: [Key]
            let pointer: [PointerEvent]
        }
        let framing = Framing(
            columns: columns, rows: rows, output: output, keys: cameraKeys.map { Key(at: $0.at, shot: $0.shot) },
            pointer: pointerEvents)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(framing)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// Every clip, in the order the README shows them.
@MainActor
let clips: [Clip] = [
    mixerClip, unicodeClip, imagesClip, glyphsClip, tablesClip, materialsClip, dragDropClip, themingClip, animationClip,
    stylesClip, tracksClip, menusClip, textEditClip, navigationClip, controlsClip, todoClip,
]

/// Scenes for reviewing a change before any clip uses it: run and played by
/// name like a clip, and left out of `list`, so nothing films them all.
@MainActor
let reviewScenes: [Clip] = [frostReviewClip, veilReviewClip]
