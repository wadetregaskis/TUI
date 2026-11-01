//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalBell.swift
//
//  The terminal's bell, rung when a control turns input away, and the
//  person's attention, asked for by the app.
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
/// It also carries the app's requests for the person's attention
/// (``RequestAttentionAction``), queued the same way: each message is a
/// desktop notification where the terminal posts one, and rings the bell
/// where it does not, which the run loop decides as it writes them.
///
/// One per ``TUIContext``, as the clipboard writer is, so two apps in one
/// process (a test suite) do not ring each other's.
package final class TerminalBell {
    // Rung from event handlers and drained by the run loop, both on the main
    // actor.
    private var owed = false

    /// The messages attention was asked with since the last frame, each once,
    /// in the order first asked.
    private var owedAttention: [String] = []

    /// How many times the bell was rung, ever — for tests, which have no
    /// terminal to hear it.
    private(set) var ringCount = 0

    /// Asks the run loop for a frame, so the bell sounds now rather than with
    /// whatever draws next.
    private let requestFrame: @Sendable () -> Void

    /// A bell whose ring asks `requestFrame` for a frame: its context's
    /// render state's, in an app.
    package init(requestFrame: @escaping @Sendable () -> Void) {
        self.requestFrame = requestFrame
    }

    /// Rings the bell at the next frame.
    package func ring() {
        ringCount += 1
        owed = true
        requestFrame()
    }

    /// Asks for the person's attention at the next frame, with `message`.
    package func requestAttention(_ message: String) {
        if !owedAttention.contains(message) { owedAttention.append(message) }
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

    /// The messages attention was asked with since the last frame, and
    /// forgets them: for the run loop to post, or to ring the bell for.
    package func takePendingAttention() -> [String] {
        defer { owedAttention.removeAll() }
        return owedAttention
    }
}

private struct TerminalBellKey: EnvironmentKey {
    static var defaultValue: TerminalBell? { nil }
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
