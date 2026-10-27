//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilities.swift
//
//  What the terminal in front of the person can do, feature by feature, as
//  far as TUI knows: the owner's item #9 (decisions TERMCAPS-API).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - TerminalCapabilities

/// What the terminal painting the app can do, feature by feature, as far as
/// TUI knows: whether it draws a curly underline, posts a notification,
/// reports a key's release, sends Option as Meta.
///
/// Read it from the environment to say, only where it is true, that something
/// the app shows does not work here, or to offer another way:
///
/// ```swift
/// @Environment(\.terminalCapabilities) private var terminal
///
/// var body: some View {
///     Text("Misspelt").underline(pattern: .curly, color: .red)
///     if terminal.status(of: .curlyUnderline) == .unsupported {
///         Text("(this terminal draws a plain line)").foregroundStyle(.tertiary)
///     }
/// }
/// ```
///
/// Each ``Feature`` is in one of three states (``Status``): supported,
/// unsupported, or undetermined — nobody has measured this terminal, nothing
/// has asked it, or nothing the person did has shown it yet. An app should not
/// tell a person "your terminal can't" about an undetermined feature. TUI
/// itself plays safe there (a plain underline, no link), as it always has.
///
/// The answers are the ones TUI acts on, from three sources, which each
/// feature's documentation names:
/// - **Its tables of terminals**, measured or documented, by which terminal
///   it identified at launch. See `Documentation/Terminals/Terminal
///   compatibility survey.md`.
/// - **The terminal's answers** to what TUI asks it at launch: the
///   graphics handshake and the kitty keyboard protocol's query. They come
///   back before the first frame is drawn.
/// - **What the person's input shows**, for what only a keypress can tell:
///   an Option chord that arrives as one shows that Option is sent as Meta.
///
/// So a feature can settle while the app runs: from undetermined to supported
/// when a keypress shows it, and under tmux back and forth as terminals
/// attach and detach (``Feature/progressReports``). Each change draws the
/// views that read the value again; nothing changes it per frame.
///
/// Read-only: an app changes what TUI sends with the switches each feature
/// names (`TerminalClient.hyperlinkSupport`, `TUI_GRAPHICS`, …), set before
/// the app runs, and the answers here follow them. Colour depth is not a feature but a level, and stays
/// `ColorDepth`, which `colorDepth` passes through.
public struct TerminalCapabilities: Hashable, Sendable {
    /// The features known to work in this terminal.
    public let supported: Feature

    /// The features known not to work in this terminal: measured, told by
    /// the terminal, or turned off by a switch.
    public let unsupported: Feature

    /// The features nobody knows about yet: neither ``supported`` nor
    /// ``unsupported``.
    public var undetermined: Feature {
        Feature.all.subtracting(supported).subtracting(unsupported)
    }

    /// What is known of a terminal TUI has not asked anything: every
    /// feature undetermined. What a view rendered outside a running app (a
    /// test, a snapshot) reads.
    package static let nothingKnown = Self(supported: [], unsupported: [])

    /// The capabilities with `supported` and `unsupported` known, and
    /// everything else undetermined. A feature in both is taken as supported.
    package init(supported: Feature, unsupported: Feature) {
        self.supported = supported
        self.unsupported = unsupported.subtracting(supported)
    }

    /// Whether `feature` works in this terminal.
    ///
    /// For a group such as ``Feature/patternedUnderline``: supported when
    /// every member is, unsupported when every member is, and undetermined
    /// otherwise — a group whose members disagree included. Ask
    /// ``supports(_:)`` or ``supportsAny(of:)`` for a group instead, or ask
    /// about each member.
    public func status(of feature: Feature) -> Status {
        if supported.isSuperset(of: feature) { return .supported }
        if unsupported.isSuperset(of: feature) { return .unsupported }
        return .undetermined
    }

    /// Whether every one of `features` is known to work in this terminal:
    /// `false` where any is unsupported or undetermined. `true` for the empty
    /// set.
    public func supports(_ features: Feature) -> Bool {
        supported.isSuperset(of: features)
    }

    /// Whether at least one of `features` is known to work in this terminal.
    /// `false` for the empty set.
    public func supportsAny(of features: Feature) -> Bool {
        !supported.isDisjoint(with: features)
    }

    /// These capabilities with `features` settled as `status`, the rest kept:
    /// how each source of answers publishes its own.
    package func settling(_ features: Feature, as status: Status) -> Self {
        var supported = supported.subtracting(features)
        var unsupported = unsupported.subtracting(features)
        switch status {
        case .supported: supported.formUnion(features)
        case .unsupported: unsupported.formUnion(features)
        case .undetermined: break
        }
        return Self(supported: supported, unsupported: unsupported)
    }

    /// These capabilities with `other`'s answers for `features` taken in place
    /// of their own.
    package func settling(_ features: Feature, from other: Self) -> Self {
        Self(
            supported: supported.subtracting(features).union(other.supported.intersection(features)),
            unsupported: unsupported.subtracting(features).union(other.unsupported.intersection(features)))
    }
}

// MARK: - Status

extension TerminalCapabilities {
    /// Whether a feature works in this terminal, as far as TUI knows.
    public enum Status: Hashable, Sendable {
        /// It works: a table of terminals says so, the terminal said so when
        /// asked, or the person's input showed it.
        case supported
        /// It does not work: a table of terminals says so, the terminal's
        /// answer said so, or a switch turned it off. TUI does not send it,
        /// or sends it knowing it is not drawn.
        case unsupported
        /// Nobody knows yet: a terminal TUI has not measured, no terminal at
        /// all, or a feature only input can show, before it has.
        case undetermined
    }
}

// MARK: - Observing input

extension TerminalCapabilities {
    /// These capabilities with what `event`, a key the terminal sent, shows,
    /// or `nil` where it shows nothing new. Asked of every key read from the
    /// terminal, and costs a comparison once a feature is settled.
    ///
    /// Only ``Feature/optionAsMeta`` is learnt this way, and only ever as
    /// supported: an Option chord on a printable key arrived as a chord.
    package func observing(_ event: KeyEvent) -> Self? {
        guard !supported.contains(.optionAsMeta), Self.showsOptionAsMeta(event) else { return nil }
        return settling(.optionAsMeta, as: .supported)
    }

    /// Whether `event` is an Option chord on a printable key that no
    /// terminal's key map is known to send in place of another key.
    ///
    /// Excluded: Option-B, -D and -F, the Emacs word keys `ESC b`, `ESC d` and
    /// `ESC f`, which key maps send for ⌥←, ⌥⌦ and ⌥→ with Option as Meta off
    /// (Apple Terminal's shipped map binds the arrows so, by the survey's
    /// reading of its Keyboard tab, and iTerm2's "Natural Text Editing"
    /// preset all three); a ⌘ chord; and a release, which repeats its press.
    static func showsOptionAsMeta(_ event: KeyEvent) -> Bool {
        guard event.alt, !event.command, event.phase != .release, case .character(let character) = event.key,
            let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
            (0x21..<0x7F).contains(scalar.value)
        else { return false }
        return !"bdf".unicodeScalars.contains(scalar)
    }
}
