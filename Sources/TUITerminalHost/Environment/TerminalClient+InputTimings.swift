//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalClient+InputTimings.swift
//
//  The host's own timings for input: how far apart two clicks may be and
//  count as a double-click, and how the text cursor blinks.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)
import WinSDK
#endif

/// What the host's settings say about how input is timed, where they say
/// anything: each `nil` where the host states nothing, so TUI's own value
/// stands.
package struct HostInputTimings: Equatable, Sendable {
    /// The longest gap between two clicks that still makes them a double-click.
    package var doubleClickInterval: Duration?

    /// How long the text cursor shows, and then how long it hides, in a blink.
    package var textCursorBlinkHalf: Duration?

    /// Whether the text cursor blinks at all: `false` where the user turned
    /// blinking off.
    package var textCursorBlinks: Bool?

    package init(doubleClickInterval: Duration? = nil, textCursorBlinkHalf: Duration? = nil, textCursorBlinks: Bool? = nil) {
        self.doubleClickInterval = doubleClickInterval
        self.textCursorBlinkHalf = textCursorBlinkHalf
        self.textCursorBlinks = textCursorBlinks
    }
}

extension TerminalClient {
    /// The host's own input timings: on Windows its double-click speed
    /// (`GetDoubleClickTime`, the Mouse control panel's) and its text cursor's
    /// blink rate (`GetCaretBlinkTime`, the Keyboard control panel's), read
    /// without starting a process; elsewhere none yet, so TUI's own timings
    /// stand there (macOS's and GNOME's settings are for the Mac to add).
    ///
    /// Counted only where the user is at this machine, as the host's other
    /// settings are (`HostSettingsRefresher`). Measured 2026-11-20 on Windows 11
    /// at its defaults: 500 ms and 530 ms.
    package static func hostInputTimings() -> HostInputTimings {
        #if os(Windows)
            windowsInputTimings(
                doubleClickMilliseconds: UInt32(GetDoubleClickTime()),
                caretBlinkMilliseconds: UInt32(GetCaretBlinkTime()))
        #else
            HostInputTimings()
        #endif
    }

    /// Windows's two answers as timings. A blink time of `INFINITE` is the
    /// cursor not blinking, Settings' "None"; 0, which either call answers
    /// for a failure, states nothing.
    package static func windowsInputTimings(
        doubleClickMilliseconds: UInt32, caretBlinkMilliseconds: UInt32
    ) -> HostInputTimings {
        var timings = HostInputTimings()
        if doubleClickMilliseconds > 0 { timings.doubleClickInterval = .milliseconds(Int(doubleClickMilliseconds)) }
        switch caretBlinkMilliseconds {
        case 0:
            break
        case .max:
            timings.textCursorBlinks = false
        default:
            timings.textCursorBlinks = true
            timings.textCursorBlinkHalf = .milliseconds(Int(caretBlinkMilliseconds))
        }
        return timings
    }
}
