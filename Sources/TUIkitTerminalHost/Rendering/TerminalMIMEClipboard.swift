//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalMIMEClipboard.swift
//
//  Whether the terminal takes kitty's clipboard protocol, OSC 5522, which
//  copies any MIME type — styled text, Markdown, a picture — where OSC 52
//  copies text alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension TerminalClient {
    /// Force the answer to ``mimeClipboard``, whatever was detected: `true`
    /// sends every terminal copy by OSC 5522, `false` never does. `nil`, the
    /// default, defers to `TUIKIT_OSC5522` (`1` or `0`), then to what the
    /// startup exchange learned.
    @MainActor public static var mimeClipboardSupport: Bool?

    /// What the startup exchange learned: the terminal answered DECRQM for
    /// private mode 5522 as a mode it implements (set or reset). Asked only
    /// of hosts ``mayAskMIMEClipboard(environment:program:)`` allows.
    @MainActor package static var mimeClipboardDetected = false

    /// Whether a copy that goes to the terminal goes by OSC 5522 — every
    /// representation the app has of it, its text among them — rather than
    /// by OSC 52, its text alone.
    ///
    /// OSC 5522 is kitty's: a write names each part's MIME type, so a picture
    /// can be copied as a picture and styled text as HTML beside its plain
    /// text, and the terminal says whether it took it. kitty (0.28 and later)
    /// is the reference implementation; Ghostty has it on its development
    /// branch (not in 1.3.1); foot has it under review. Measured 2026-10-17:
    /// iTerm2 3.6 answers the mode query "permanently reset", Apple Terminal
    /// and Warp do not answer it, and none of the three took a write. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "OSC 5522
    /// clipboard: any MIME type".
    @MainActor public static var mimeClipboard: Bool {
        mimeClipboard(
            environment: ProcessInfo.processInfo.environment, override: mimeClipboardSupport,
            detected: mimeClipboardDetected)
    }

    /// The ladder behind ``mimeClipboard``, posed on its inputs.
    static func mimeClipboard(environment: [String: String], override: Bool?, detected: Bool) -> Bool {
        if let override { return override }
        switch environment["TUIKIT_OSC5522"] {
        case "1": return true
        case "0": return false
        default: return detected
        }
    }

    /// Whether the startup exchange may ask the terminal about mode 5522.
    ///
    /// DECRQM (`CSI ? Ps $ p`) is the one CSI shape Apple Terminal prints
    /// rather than consumes, so it is asked only of hosts known to consume
    /// it and likely to say yes: Ghostty, and kitty, WezTerm and foot where
    /// the environment names them. iTerm2 answers it, "permanently reset",
    /// so asking it would only cost a round trip; and tmux, which would
    /// answer for itself, passes no OSC 5522 on.
    static func mayAskMIMEClipboard(environment: [String: String], program: Program) -> Bool {
        switch program {
        case .ghostty: true
        case .unidentified: namesClipboardWritingTerminal(environment)
        case .appleTerminal, .iTerm2, .warp, .tmux: false
        }
    }

    /// ``mayAskMIMEClipboard(environment:program:)`` for this process.
    @MainActor package static var mayAskMIMEClipboard: Bool {
        mayAskMIMEClipboard(environment: ProcessInfo.processInfo.environment, program: current.program)
    }
}
