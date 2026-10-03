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
/// Read from what the terminal sends, which is less than a window server
/// knows, in three ways:
///
/// - **Every press is ``Phases/down``.** A terminal sends a held
///   key's auto-repeats as further presses, identical to the first, and sends
///   nothing at all when a key is released. So a handler for
///   ``Phases/repeat`` is handed every press too, labelled
///   `.down`, and there is no `.up` to ask for.
/// - **``modifiers`` holds what the terminal reports**: Control, Option and
///   Shift. Never Command, Caps Lock or the numeric pad (see
///   ``EventModifiers``), and not the numeric-pad flag macOS sets on an arrow
///   key either.
/// - **A key the terminal composed arrives composed.** Without "Option as
///   Meta", Option-A arrives as "å" with no modifier, where macOS reports "a"
///   and Option; and Control-Shift-A arrives as Control-A, because the control
///   byte has no case.
public struct KeyPress: Sendable, CustomDebugStringConvertible {
    /// The phase of this press: always ``Phases/down`` in a
    /// terminal — see the type's documentation.
    public let phase: Phases

    /// The key that was pressed — `"A"` for Shift-A, ``KeyEquivalent/upArrow``
    /// for the up arrow.
    public let key: KeyEquivalent

    /// The characters the key produces as if no modifier but Shift applied:
    /// `"a"` for Control-A, `"A"` for Shift-A, and for a key that types
    /// nothing, the private-use scalar that stands for it (`"\u{F700}"` for the
    /// up arrow), as on macOS.
    public let characters: String

    /// The modifier keys held with the key: Control, Option and Shift, which
    /// are all a terminal reports.
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
        self.init(phase: .down, key: key, characters: String(key.character), modifiers: EventModifiers(event))
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
    /// There is no `.up`: a terminal never says that a key was released, so a
    /// handler for the release could never run, and asking for it does not
    /// compile. ``repeat`` is accepted, but a terminal cannot tell an
    /// auto-repeat from a press, so it hears every press (see ``KeyPress``).
    public struct Phases: OptionSet, Sendable, CustomDebugStringConvertible {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The user pressed a key — and, in a terminal, each auto-repeat of a
        /// held key, which arrives as another press.
        public static let down = Self(rawValue: 1 << 0)

        /// The user held a key down to repeat it. A terminal sends each repeat
        /// as another press, indistinguishable from the first, so a handler for
        /// this phase hears every press.
        public static let `repeat` = Self(rawValue: 1 << 1)

        /// SwiftUI's release bit, kept so that ``all`` and a raw value read
        /// back as SwiftUI's do. Not public: nothing a terminal sends has it.
        static let up = Self(rawValue: 1 << 2)

        /// Every phase: every press, in a terminal.
        public static let all = Self(rawValue: .max)

        /// `.down`, `[.down, .repeat]`, `.all` — SwiftUI's spelling.
        public var debugDescription: String {
            if self == .all { return ".all" }
            let names = [(Self.down, ".down"), (.repeat, ".repeat"), (.up, ".up")]
                .filter { contains($0.0) }.map(\.1)
            return names.count == 1 ? names[0] : "[" + names.joined(separator: ", ") + "]"
        }

        /// Whether a handler for these phases hears a press: any phase a
        /// terminal's press could be, which is a press or a repeat.
        var hearsTerminalPress: Bool {
            !isDisjoint(with: [.down, .repeat])
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
