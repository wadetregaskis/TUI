//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyPress.swift
//
//  SwiftUI's description of a key press, as `onKeyPress` hands it to an
//  action, built from the terminal's `KeyEvent`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Key Press

/// A key press, as ``View/onKeyPress(phases:action:)`` and its siblings hand it
/// to their action — SwiftUI's `KeyPress`.
///
/// Read from what the terminal sends, which can be less than a window server
/// knows, in three ways:
///
/// - **The phases depend on the terminal.** In the legacy key encodings every
///   terminal speaks, every press is ``Phases/down``: a held key's
///   auto-repeats arrive as further presses, identical to the first, and a
///   release sends nothing. So there a ``Phases/repeat`` handler is handed
///   every press, labelled `.down`, and a ``Phases/up`` handler never runs.
///   Where the terminal speaks the kitty keyboard protocol, which TUIkit turns
///   on wherever it can, all three phases are reported as SwiftUI reports
///   them. ``EnvironmentValues/keyboardReporting`` says which is the case.
/// - **``modifiers`` holds what the terminal reports**: Control, Option and
///   Shift; and Caps Lock and the numeric pad where it speaks the kitty
///   keyboard protocol. Never Command (see ``EventModifiers``), and not the
///   numeric-pad flag macOS sets on an arrow key either.
/// - **A key the terminal composed arrives composed.** Without "Option as
///   Meta", Option-A arrives as "å" with no modifier, where macOS reports "a"
///   and Option; and Control-Shift-A arrives as Control-A, because the control
///   byte has no case.
public struct KeyPress: Sendable, CustomDebugStringConvertible {
    /// The phase of the key-press event (`.down`, `.repeat`, or `.up`).
    ///
    /// Always ``Phases/down`` from a terminal in its legacy encodings, where
    /// repeats arrive as presses and releases never arrive; see the type's
    /// documentation and ``EnvironmentValues/keyboardReporting``.
    public let phase: Phases

    /// The key that was pressed — `"A"` for Shift-A, ``KeyEquivalent/upArrow``
    /// for the up arrow.
    public let key: KeyEquivalent

    /// The characters the key produces as if no modifier but Shift applied:
    /// `"a"` for Control-A, `"A"` for Shift-A, and for a key that types
    /// nothing, the private-use scalar that stands for it (`"\u{F700}"` for the
    /// up arrow), as on macOS.
    public let characters: String

    /// The modifier keys held with the key: Control, Option and Shift, and
    /// Caps Lock and the numeric pad where the terminal speaks the kitty
    /// keyboard protocol (``EnvironmentValues/keyboardReporting``).
    public let modifiers: EventModifiers

    /// `KeyPress(.down, "a")`, SwiftUI's spelling.
    public var debugDescription: String {
        "KeyPress(\(phase.debugDescription), \"\(characters)\")"
    }

    /// The press `event` describes, or `nil` for one that is not a key press:
    /// a bracketed paste, which SwiftUI delivers as a paste command instead.
    init?(_ event: KeyEvent) {
        let key: KeyEquivalent
        switch event.key {
        case .character(let character):
            key = KeyEquivalent(character)
        case .tab where event.shift:
            // AppKit's back-tab character, which is what SwiftUI reports for
            // Shift-Tab: `onKeyPress(.tab)` does not hear it.
            key = KeyEquivalent("\u{19}")
        case .paste:
            return nil
        default:
            guard let equivalent = Self.equivalents[event.key] else { return nil }
            key = equivalent
        }
        self.init(
            phase: Phases(event.phase), key: key, characters: String(key.character),
            modifiers: EventModifiers(event))
    }

    /// A press with these fields, for the framework and its tests: SwiftUI's
    /// has no public initialiser either.
    init(phase: Phases = .down, key: KeyEquivalent, characters: String, modifiers: EventModifiers = []) {
        self.phase = phase
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
    }

    /// The parsed keys that type nothing, as the ``KeyEquivalent`` SwiftUI
    /// reports for each: the named ones, and AppKit's function-key block for
    /// F1…F20 (`NSF1FunctionKey` is U+F704).
    private static let equivalents: [Key: KeyEquivalent] = {
        var table: [Key: KeyEquivalent] = [
            .enter: .return, .escape: .escape, .tab: .tab, .space: .space,
            .backspace: .delete, .delete: .deleteForward,
            .up: .upArrow, .down: .downArrow, .left: .leftArrow, .right: .rightArrow,
            .home: .home, .end: .end, .pageUp: .pageUp, .pageDown: .pageDown,
        ]
        let functionKeys: [Key] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        ]
        for (offset, functionKey) in functionKeys.enumerated() {
            if let scalar = Unicode.Scalar(UInt32(0xF704 + offset)) {
                table[functionKey] = KeyEquivalent(Character(scalar))
            }
        }
        return table
    }()
}

// MARK: - Phases

extension KeyPress {
    /// The phases of a key press a handler asks for — SwiftUI's
    /// `KeyPress.Phases`.
    ///
    /// All three are reported where the terminal speaks the kitty keyboard
    /// protocol (``KeyboardReporting/reportsRepeats``,
    /// ``KeyboardReporting/reportsReleases``). In the legacy encodings a
    /// terminal cannot tell an auto-repeat from a press, so a handler for
    /// ``down`` or ``repeat`` hears every press, and it never reports a
    /// release, so an ``up`` handler never runs: offer a fallback there, by
    /// reading ``EnvironmentValues/keyboardReporting``.
    public struct Phases: OptionSet, Sendable, CustomDebugStringConvertible {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The user pressed down on a key. In a terminal's legacy encodings,
        /// also each auto-repeat of a held key, which arrives as another
        /// press.
        public static let down = Self(rawValue: 1 << 0)

        /// The user held a key down to repeat it. In a terminal's legacy
        /// encodings each repeat arrives as another press, indistinguishable
        /// from the first, so a handler for this phase hears every press.
        public static let `repeat` = Self(rawValue: 1 << 1)

        /// The user released a key. Reported only where the terminal speaks
        /// the kitty keyboard protocol (``KeyboardReporting/reportsReleases``);
        /// elsewhere a handler for it never runs.
        public static let up = Self(rawValue: 1 << 2)

        /// A value that matches all key press phases.
        public static let all = Self(rawValue: .max)

        /// `.down`, `[.down, .repeat]`, `.all` — SwiftUI's spelling.
        public var debugDescription: String {
            if self == .all { return ".all" }
            let names = [(Self.down, ".down"), (.repeat, ".repeat"), (.up, ".up")]
                .filter { contains($0.0) }.map(\.1)
            return names.count == 1 ? names[0] : "[" + names.joined(separator: ", ") + "]"
        }

        /// The phase a terminal reported for one key event.
        init(_ phase: KeyEvent.Phase) {
            switch phase {
            case .press: self = .down
            case .repeat: self = .repeat
            case .release: self = .up
            }
        }

        /// Whether a handler for these phases hears an event in `phase`.
        ///
        /// A repeat or a release comes only from a terminal that reports
        /// them, so it is exact. A press is exact only there too: in a legacy
        /// encoding a held key's repeats arrive as more presses, so a press
        /// may be a repeat, and a handler for either phase hears it — the
        /// default `[.down, .repeat]` means what it means in SwiftUI, and a
        /// `.down`-only or `.repeat`-only handler over-fires rather than
        /// silently missing anything.
        ///
        /// - Parameters:
        ///   - phase: The event's phase.
        ///   - repeatsReported: Whether the terminal tells a repeat from a
        ///     press, which makes a press exact.
        func hears(_ phase: KeyEvent.Phase, repeatsReported: Bool) -> Bool {
            switch phase {
            case .press:
                return repeatsReported ? contains(.down) : !isDisjoint(with: [.down, .repeat])
            case .repeat: return contains(.repeat)
            case .release: return contains(.up)
            }
        }
    }

    /// What a key-press action did with the press — SwiftUI's
    /// `KeyPress.Result`.
    public enum Result: Sendable, Hashable {
        /// The action consumed the press: nothing further hears it.
        case handled
        /// The action ignored the press, which goes on to the next handler and
        /// then to the focused control.
        case ignored
    }
}
