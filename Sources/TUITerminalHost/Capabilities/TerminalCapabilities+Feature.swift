//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilities+Feature.swift
//
//  The features a terminal may or may not have, one member per style, and
//  the groups that ask about several at once.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Feature

extension TerminalCapabilities {
    /// Features a terminal may or may not have: one member for each, and
    /// groups of them (``patternedUnderline``, ``textDecorations``,
    /// ``hostIntegration``, ``keyboard``) for asking about several at once.
    ///
    /// Each member's documentation says how TUI finds out — from its table
    /// of terminals, from the terminal's answer to a question, or from the
    /// person's input — and whether that can settle on a given terminal.
    public struct Feature: OptionSet, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        // MARK: Text decorations

        /// `underline(pattern: .double)` draws two lines.
        ///
        /// From TUI's table of measured terminals (`TerminalHost.lineStyles`,
        /// read by the owner on 2026-10-18), at launch: supported on Ghostty,
        /// iTerm2 and Warp; unsupported on Apple Terminal, where the text gets
        /// a single line. Undetermined for the run on every other terminal,
        /// which gets a single line too, and under tmux, which draws the
        /// style in each terminal attached that can and a single line in the
        /// others.
        public static let doubleUnderline = Self(rawValue: 1 << 0)

        /// `underline(pattern: .curly)` draws a wavy line.
        ///
        /// From the table, at launch: supported on Ghostty and iTerm2;
        /// unsupported on Warp and Apple Terminal, where the text gets a plain
        /// line. Undetermined elsewhere, as ``doubleUnderline`` is.
        public static let curlyUnderline = Self(rawValue: 1 << 1)

        /// `underline(pattern: .dot)` draws a dotted line. Settled as
        /// ``curlyUnderline`` is.
        public static let dottedUnderline = Self(rawValue: 1 << 2)

        /// `underline(pattern: .dash)` draws a dashed line. Settled as
        /// ``curlyUnderline`` is.
        public static let dashedUnderline = Self(rawValue: 1 << 3)

        /// An underline's own colour, `underline(_:pattern:color:)`, is drawn.
        ///
        /// From the table, at launch: supported on Ghostty and iTerm2;
        /// unsupported on Warp and Apple Terminal, where the line takes the
        /// text's colour. Undetermined elsewhere, as ``doubleUnderline`` is.
        public static let underlineColor = Self(rawValue: 1 << 4)

        /// `strikethrough()` draws a line through the text.
        ///
        /// From the table, at launch: supported on Ghostty, iTerm2 and Warp;
        /// unsupported on Apple Terminal, which draws the text with no line
        /// (measured, 455.1). Undetermined elsewhere, as ``doubleUnderline``
        /// is.
        public static let strikethrough = Self(rawValue: 1 << 5)

        /// A strikethrough's own colour, `strikethrough(_:color:)`, is drawn.
        ///
        /// From the table, at launch: supported on iTerm2 alone; unsupported
        /// on Ghostty, which strikes through in the text's colour, on Warp,
        /// which draws no line colour at all, and on Apple Terminal.
        /// Undetermined elsewhere, as ``doubleUnderline`` is.
        public static let strikethroughColor = Self(rawValue: 1 << 6)

        // MARK: Pictures

        /// An `Image` of a bitmap draws as a picture, in the terminal's own
        /// pixels (the kitty graphics protocol), rather than as character art.
        ///
        /// Asked at launch, before the first frame: TUI places a picture
        /// and waits for the terminal to acknowledge it. Supported where it
        /// does; unsupported where it does not, and on Apple Terminal, which is
        /// not asked because it prints the question. Settled on every terminal
        /// TUI runs in. `TerminalClient.graphicsSupport` or
        /// `TUIKIT_GRAPHICS` (`1` or `0`) settles it either way without asking.
        public static let pictures = Self(rawValue: 1 << 16)

        // MARK: Host integration

        /// A `Link`, and a link in Markdown text, is a link the terminal
        /// follows (OSC 8).
        ///
        /// From TUI's table, at launch: supported on iTerm2, Ghostty and
        /// GNOME Terminal; unsupported on Apple Terminal and Warp (which
        /// follows links only off the alternate screen). Undetermined on a
        /// terminal TUI did not identify, which is sent no link, and under
        /// tmux, which keeps the link and passes it only to the terminals
        /// attached that it credits with links. `TerminalClient.hyperlinkSupport`
        /// or `TUIKIT_HYPERLINKS` (`1` or `0`) settles it either way.
        public static let hyperlinks = Self(rawValue: 1 << 24)

        /// A copy reaches the clipboard through the terminal (OSC 52), where
        /// no clipboard of this machine's is the person's.
        ///
        /// From TUI's table, at launch: supported on Ghostty (and kitty,
        /// WezTerm and foot, known by their own variables); unsupported on
        /// Apple Terminal, Warp and GNOME Terminal. Undetermined on iTerm2,
        /// which writes only with a setting no program can read; under tmux
        /// and GNU screen, whose own options decide at each copy; and on a
        /// terminal TUI did not identify. `TerminalClient.clipboardWriteSupport`
        /// or `TUIKIT_OSC52` (`1` or `0`) settles it either way.
        public static let clipboardWrites = Self(rawValue: 1 << 25)

        /// `requestAttention(_:)` posts a desktop notification (OSC 9) rather
        /// than ringing the bell.
        ///
        /// From TUI's table, at launch: supported on Ghostty and iTerm2;
        /// unsupported on Apple Terminal, Warp, GNOME Terminal and tmux, which
        /// passes none on. Undetermined on a terminal TUI did not identify.
        /// `TUIKIT_NOTIFICATIONS` (`1` or `0`) settles it either way.
        public static let notifications = Self(rawValue: 1 << 26)

        /// `terminalProgress(_:)` shows as a bar the terminal draws on its tab
        /// or its window.
        ///
        /// From TUI's table, at launch: supported on Ghostty and iTerm2;
        /// unsupported on Apple Terminal, Warp and GNOME Terminal. Under tmux
        /// it follows the terminals attached, asked again as they attach and
        /// detach, and can change while the app runs: supported while every
        /// one draws the bar tmux passes on. Undetermined on a terminal TUI
        /// did not identify. `TUIKIT_PROGRESS` (`1` or `0`) settles it either
        /// way.
        public static let progressReports = Self(rawValue: 1 << 27)

        /// `pointerStyle(_:)` changes the mouse pointer's shape (OSC 22).
        ///
        /// From TUI's table, at launch: supported where TUI found a
        /// terminal documented to take one (Ghostty, iTerm2, kitty, foot,
        /// xterm); unsupported on Apple Terminal and Warp, which document
        /// none. Undetermined on GNOME Terminal, under tmux, and on a terminal
        /// TUI did not identify. `TerminalClient.pointerShapeSupport` or
        /// `TUIKIT_POINTER_SHAPES` (`1` or `0`) settles it either way.
        public static let pointerShapes = Self(rawValue: 1 << 28)

        // MARK: Keyboard

        /// Escape, and Ctrl-H, -I, -J, -M and -[, arrive as themselves rather
        /// than as Backspace, Tab, Return and Escape.
        ///
        /// This and the six below are asked at launch, before the first frame:
        /// TUI turns on the kitty keyboard protocol where the terminal
        /// answers its query, and each is supported where the terminal took
        /// the part of it this needs. Unsupported where it does not speak the
        /// protocol, on Apple Terminal, which is not asked, and wherever
        /// `TUIKIT_KEYBOARD_PROTOCOL=0` keeps TUI from asking. Settled on
        /// every terminal TUI runs in.
        ///
        /// Where it is supported, a binding on one of those chords fires, and
        /// one that nothing binds still acts as the key it used to arrive as.
        /// Where it is not, a shortcut on one can never fire
        /// (`KeyboardShortcut.isDeliverableInTerminal`).
        public static let disambiguatedKeys = Self(rawValue: 1 << 32)

        /// A Control or Option chord with Shift arrives as its shifted key, so
        /// Ctrl-Shift-Z is not Ctrl-Z, and Ctrl-Shift-minus (Ctrl-_) is not
        /// Ctrl-minus. Where it is not supported, Shift on a Control chord is
        /// lost, as the legacy encodings' control byte has no case. Asked at
        /// launch, as ``disambiguatedKeys`` is.
        public static let shiftedKeys = Self(rawValue: 1 << 33)

        /// A held key's repeats are told apart from its press
        /// (`KeyPress.Phases.repeat`): a `.repeat` handler hears only repeats,
        /// and a `.down` handler only the press. Where it is not supported,
        /// every repeat arrives as another press, and a handler for either
        /// phase hears them all. Asked at launch, as ``disambiguatedKeys`` is.
        public static let keyRepeats = Self(rawValue: 1 << 34)

        /// A key's release is reported, so a `KeyPress.Phases.up` handler
        /// runs; where it is not supported, one never does. Asked at launch,
        /// as ``disambiguatedKeys`` is.
        public static let keyReleases = Self(rawValue: 1 << 35)

        /// A modifier key pressed or released on its own is reported — the
        /// kitty protocol's "report all keys" mode — so
        /// `onModifierKeysChanged(mask:initial:_:)` and
        /// `modifierKeyAlternate(_:_:)` see it. Asked at launch, as
        /// ``disambiguatedKeys`` is.
        public static let modifierKeys = Self(rawValue: 1 << 36)

        /// Caps Lock's state is reported on every key (`EventModifiers.capsLock`).
        /// Asked at launch, as ``disambiguatedKeys`` is.
        public static let capsLock = Self(rawValue: 1 << 37)

        /// A key on the numeric keypad is told apart from its twin on the main
        /// keyboard (`EventModifiers.numericPad`). Asked at launch, as
        /// ``disambiguatedKeys`` is.
        public static let numericPad = Self(rawValue: 1 << 38)

        /// The terminal sends Option as Meta, so an Option chord on a letter
        /// reaches the app as that chord (⌥X) rather than as the character
        /// Option composes (≈).
        ///
        /// No terminal can be asked this; it is a setting of the person's
        /// (Apple Terminal's "Use Option as Meta key", iTerm2's "Esc+",
        /// Ghostty's `macos-option-as-alt`). So it is learnt from the person's
        /// input: supported from the first Option chord on a printable key
        /// that arrives as one — `ESC x`, or a kitty protocol report with the
        /// Option bit — Option-B, -D and -F aside, which key maps send for
        /// ⌥←, ⌥⌦ and ⌥→ with the setting off. It never settles as
        /// unsupported: a composed character cannot be told from one typed on
        /// a keyboard layout that has it, so where Option composes it stays
        /// undetermined for the run. An Escape pressed and followed by a key
        /// within one read arrives as an Option chord too, and counts.
        public static let optionAsMeta = Self(rawValue: 1 << 39)

        // MARK: Groups

        /// Curly, dotted and dashed underlines: what most terminals draw all
        /// of or none of.
        public static let patternedUnderline: Self = [.curlyUnderline, .dottedUnderline, .dashedUnderline]

        /// Every underline style, the underline's colour, the strikethrough
        /// and its colour.
        public static let textDecorations: Self = [
            .doubleUnderline, .patternedUnderline, .underlineColor, .strikethrough, .strikethroughColor,
        ]

        /// What the app asks of the terminal beyond its cells: links, the
        /// clipboard, notifications, a progress bar, the pointer's shape.
        public static let hostIntegration: Self = [
            .hyperlinks, .clipboardWrites, .notifications, .progressReports, .pointerShapes,
        ]

        /// Everything about keys beyond the keys themselves: what the kitty
        /// keyboard protocol reports, and Option as Meta.
        public static let keyboard: Self = [
            .disambiguatedKeys, .shiftedKeys, .keyRepeats, .keyReleases, .modifierKeys, .capsLock, .numericPad,
            .optionAsMeta,
        ]

        /// Every feature.
        package static let all: Self = [.textDecorations, .pictures, .hostIntegration, .keyboard]
    }
}
