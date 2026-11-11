//  🖥️ TUI — A Terminal UI framework for Swift
//  SensoryFeedback.swift
//
//  SwiftUI's kinds of sensory feedback: the two a terminal can play, on its
//  bell, and the rest refused at compile time.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Sensory Feedback

/// A kind of feedback that ``View/sensoryFeedback(_:trigger:)`` plays: on a
/// terminal, its bell.
///
/// A terminal has no haptics and no sounds of its own choosing, only the bell
/// (`BEL`), which it sounds, flashes or marks as its user has set it. So the
/// two kinds that say something went wrong — ``error`` and ``warning`` — ring
/// it, and the rest, which a terminal could not tell apart from them or make
/// felt at all, fail to compile, with a message saying so. That keeps a
/// `.success` from ringing what reads as "no", and a `.selection` from
/// ringing on every arrow.
///
/// The same bell an app rings itself with ``EnvironmentValues/ringBell``, and
/// TUI's own controls when they refuse input: one ring a frame, whoever rang.
///
/// Matches SwiftUI's struct, with its static members.
public struct SensoryFeedback: Equatable, Sendable {
    /// The kinds a terminal can play.
    private enum Kind: Equatable, Sendable {
        case warning, error
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// Something went wrong, but not badly: rings the terminal's bell.
    public static let warning = Self(.warning)

    /// Something failed: rings the terminal's bell.
    public static let error = Self(.error)
}

// MARK: - Refused kinds

// SwiftUI's other kinds. Each is unavailable, so a program that asks for one
// fails to compile, with the way out in the message, rather than ringing a
// bell that says the wrong thing or ringing nothing. Their bodies never run.
// No documentation, and long lines: nothing here reaches a reader except its
// message, and a message has to be one string literal.
// swiftlint:disable missing_docs line_length
extension SensoryFeedback {
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var success: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var selection: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var increase: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var decrease: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var start: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var stop: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var alignment: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var levelChange: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var pathComplete: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static var impact: SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static func impact(weight: Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static func impact(flexibility: Flexibility, intensity: Double = 1.0) -> SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static func selection(_ feedback: SelectionFeedback) -> SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static func press(_ feedback: PressFeedback) -> SensoryFeedback { .warning }

    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    @_alwaysEmitIntoClient
    public static func release(_ feedback: ReleaseFeedback) -> SensoryFeedback { .warning }

    // The arguments of the refused kinds above, refused with them. Enums with
    // cases rather than SwiftUI's structs with static members: nothing can
    // make a value of either, so nothing tells them apart, and a case needs
    // no body.

    /// How heavy an impact feels: refused with `impact`.
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    public enum Weight: Equatable, Sendable {
        case light, medium, heavy
    }

    /// How flexible the objects in an impact feel: refused with `impact`.
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    public enum Flexibility: Equatable, Sendable {
        case rigid, solid, soft
    }

    /// A selection's feedback: refused with `selection(_:)`.
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    public enum SelectionFeedback: Hashable, Sendable {
        case maximum, minimum, on, off
    }

    /// A press's feedback: refused with `press(_:)`.
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    public enum PressFeedback: Hashable, Sendable {
        case button, buttonIconOnly, slider, toggle, tab
    }

    /// A release's feedback: refused with `release(_:)`.
    @available(*, unavailable, message: "A terminal can't make this felt. Use .error or .warning, which ring the terminal's bell, or ring it yourself with @Environment(\\.ringBell).")
    public enum ReleaseFeedback: Hashable, Sendable {
        case slider
    }
}
// swiftlint:enable missing_docs line_length
