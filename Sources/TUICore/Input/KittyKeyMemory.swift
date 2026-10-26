//  🖥️ TUI — A Terminal UI framework for Swift
//  KittyKeyMemory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - What the decoder remembers between reports

/// What ``KittyKeyDecoder`` remembers from one key report to the next.
///
/// A report is decoded on its own, but a key is not one report: it goes down,
/// may repeat, and comes up, and the protocol does not describe the up the way
/// it described the down. A press carries the text the key typed — `A` under
/// Caps Lock, `é` after a dead key, a word from an input method — and a
/// release carries none, only the key's code. Decoded on its own, the release
/// of the key that typed `A` under Caps Lock is `a`, and the release of the key
/// that typed `é` is `e`, so `onKeyPress("A", phases: .up)` would never hear
/// the key it heard go down. So the press is remembered, by the key's code,
/// and its release delivers the same key events again.
///
/// The modifier keys are remembered too, each by its own code, because the
/// report of one says nothing about its twin: with both Shift keys held,
/// releasing one leaves Shift held. And the state last reported is kept, so a
/// key report whose modifier bits disagree with it — a modifier's release
/// that went to another window, a press made before the app started —
/// reports the state again before its key (see
/// ``KittyKeyDecoder/decode(_:memory:)``).
///
/// One per terminal, kept by the input parser while the protocol is on and
/// forgotten when it is popped.
package struct KittyKeyMemory: Sendable {
    /// What each key that is down delivered when it went down (or last
    /// repeated), by its code: what its release delivers again.
    var pressed: [Int: [KeyEvent]] = [:]

    /// The modifier keys down, by code: the left and right Shift are two.
    var heldModifierKeys: Set<Int> = []

    /// The modifier state last reported as `.modifierKeys`: nothing held, and
    /// Caps Lock off, until a report says otherwise — what the app's modifier
    /// state starts as. `nil` for a decoder that keeps no state between
    /// reports and reports none of its own (``KittyKeyDecoder/decode(_:)``).
    var reportedState: ModifierKeyState? = ModifierKeyState()

    package init() {}

    /// A memory for one report on its own: it reports no modifier state the
    /// report does not carry itself.
    static var oneReport: Self {
        var memory = Self()
        memory.reportedState = nil
        return memory
    }

    /// Notes what the key `code` delivered going down or repeating.
    mutating func press(_ code: Int, delivered events: [KeyEvent]) {
        guard code != 0, !events.isEmpty else { return }
        pressed[code] = events
    }

    /// What the key `code` delivered going down, as a release; `nil` for a key
    /// not seen going down (it went down before the protocol was on).
    mutating func release(_ code: Int) -> [KeyEvent]? {
        pressed.removeValue(forKey: code)?.map { press in
            KeyEvent(
                key: press.key, ctrl: press.ctrl, alt: press.alt, shift: press.shift, command: press.command,
                phase: .release,
                capsLock: press.capsLock, numericPad: press.numericPad)
        }
    }
}
