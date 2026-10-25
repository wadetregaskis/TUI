//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Clip.swift
//
//  What a clip is: a TUIkit app, and the script the player plays against it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// One step of a clip's script, played by the player in order.
///
/// A script is a list of moves on one clock — the player's — that starts when
/// the app has drawn its first frame and settled, so the same script lands at
/// the same instants on every run. Keys are bytes typed into the app's
/// terminal, read by TUIkit's own parser and dispatched as a keypress is; a cue
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

    /// Tab: the next focus stop.
    static let tab = Step.keys("\t")
    /// Shift+Tab: the previous focus stop.
    static let backTab = Step.keys("\u{1B}[Z")
    /// Space: presses the focused button, flips the focused toggle.
    static let space = Step.keys(" ")
    /// Return.
    static let enter = Step.keys("\r")
    /// Escape.
    static let escape = Step.keys("\u{1B}")
    /// The arrow keys.
    static let up = Step.keys("\u{1B}[A")
    static let down = Step.keys("\u{1B}[B")
    static let right = Step.keys("\u{1B}[C")
    static let left = Step.keys("\u{1B}[D")

    /// Types `text` a character at a time, `interval` seconds apart, as a
    /// person would: one frame per keystroke, not the whole word at once.
    static func type(_ text: String, interval: Double = 0.09) -> [Step] {
        text.flatMap { [Step.keys(String($0)), .wait(interval)] }
    }

    /// `step`, `count` times, `interval` seconds apart.
    static func `repeat`(_ step: Step, _ count: Int, interval: Double) -> [Step] {
        (0..<count).flatMap { _ in [step, .wait(interval)] }
    }
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
    /// The script, played once the app has settled.
    let script: [Step]
    /// Runs the app: called in the child the player starts under its own
    /// pseudo-terminal, and does not return until the app quits.
    let run: @MainActor () async -> Void

    /// How long the script runs, waits included.
    var duration: Double {
        script.reduce(0) { total, step in
            if case .wait(let seconds) = step { total + seconds } else { total }
        }
    }
}

/// Every clip, in the order the README shows them.
@MainActor
let clips: [Clip] = [themingClip, controlsClip]
