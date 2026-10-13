//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalBell.swift
//
//  The terminal's bell, rung when a control turns input away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The terminal's bell: one `BEL` (`0x07`), which the terminal sounds or
/// flashes as its user has set it.
///
/// Rung when a control turns input away rather than taking it — a character
/// a field's ``TextContentType`` does not allow, typed or pasted — so that
/// what was typed is not dropped silently (the owner's ruling on deviation
/// T8, 2026-10-13).
///
/// A ring is queued rather than written, as an OSC 52 copy is
/// (``ClipboardWriter``): the run loop owns the terminal and writes the bell
/// at the start of its next frame (``takePending()``), which a ring asks for.
/// However often it is rung between two frames — a paste that drops a dozen
/// characters, a key held down — the frame rings it once.
///
/// One per ``TUIContext``, as the clipboard writer is, so two apps in one
/// process (a test suite) do not ring each other's.
package final class TerminalBell: @unchecked Sendable {
    // Rung from event handlers and drained by the run loop, both on the main
    // actor; `@unchecked` because the environment that carries the bell is
    // `Sendable`.
    private var owed = false

    /// How many times the bell was rung, ever — for tests, which have no
    /// terminal to hear it.
    private(set) var ringCount = 0

    /// Asks the run loop for a frame, so the bell sounds now rather than with
    /// whatever draws next.
    private let requestFrame: @Sendable () -> Void

    package init(requestFrame: @escaping @Sendable () -> Void = { AppState.shared.setNeedsRender() }) {
        self.requestFrame = requestFrame
    }

    /// Rings the bell at the next frame.
    package func ring() {
        ringCount += 1
        owed = true
        requestFrame()
    }

    /// The bytes owed to the terminal — one `BEL`, or nothing — and forgets
    /// them. The run loop writes them with its frame's other out-of-band
    /// writes, ahead of every cell: a bell draws nothing and moves no cursor.
    package func takePending() -> String {
        guard owed else { return "" }
        owed = false
        return "\u{07}"
    }
}

private struct TerminalBellKey: EnvironmentKey {
    static let defaultValue: TerminalBell? = nil
}

extension EnvironmentValues {
    /// The running app's terminal bell — its context's, handed down each
    /// frame (`applyRuntimeServices(from:)`) — or `nil` where no context's
    /// services reached, and nothing could hear it.
    package var terminalBell: TerminalBell? {
        get { self[TerminalBellKey.self] }
        set { self[TerminalBellKey.self] = newValue }
    }
}
