//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCapabilitiesEnvironment.swift
//
//  `\.terminalCapabilities`, the colour depth beside it, and the keyboard
//  features the kitty keyboard protocol's negotiation settles.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitTerminalHost

// MARK: - Colour depth

extension TerminalCapabilities {
    /// How many colours the terminal draws: ``ColorDepth/current``, read as it
    /// is asked for.
    ///
    /// A level rather than a feature, so it is not among ``supported`` and
    /// ``unsupported``; and kept where it was, so that there is one answer, not
    /// a copy that could fall behind an app that changes it.
    public var colorDepth: ColorDepth {
        ColorDepth.current
    }
}

// MARK: - The keyboard

extension TerminalCapabilities {
    /// The keyboard features the kitty keyboard protocol's negotiation decided
    /// (``Feature/disambiguatedKeys`` to ``Feature/numericPad``): each
    /// supported where `reporting` says the terminal reports it, else
    /// unsupported. Every other feature undetermined.
    package static func keyboard(_ reporting: KeyboardReporting) -> Self {
        nothingKnown
            .settling(.disambiguatedKeys, drawn: reporting.disambiguatesKeys)
            .settling(.shiftedKeys, drawn: reporting.reportsShiftedKeys)
            .settling(.keyRepeats, drawn: reporting.reportsRepeats)
            .settling(.keyReleases, drawn: reporting.reportsReleases)
            .settling(.modifierKeys, drawn: reporting.reportsModifierKeys)
            .settling(.capsLock, drawn: reporting.reportsLockStates)
            .settling(.numericPad, drawn: reporting.reportsNumericPad)
    }

    /// The features ``keyboard(_:)`` settles.
    package static let negotiatedKeyboard: Feature = [
        .disambiguatedKeys, .shiftedKeys, .keyRepeats, .keyReleases, .modifierKeys, .capsLock, .numericPad,
    ]
}

// MARK: - Environment key

private struct TerminalCapabilitiesKey: EnvironmentKey {
    /// A view rendered outside a running app has no terminal behind it to ask.
    static let defaultValue = TerminalCapabilities.nothingKnown
}

extension EnvironmentValues {
    /// What the terminal painting the app can do, feature by feature, as far
    /// as TUIkit knows — see ``TerminalCapabilities``.
    ///
    /// Published by the run loop: at launch from TUIkit's tables and the
    /// terminal's answers, and again when the person's input shows a feature
    /// or, under tmux, the terminals attached change. A view that reads it is
    /// drawn again when it changes. Read-only, because no view can change
    /// what the terminal does. Every feature is undetermined outside a running
    /// app.
    public package(set) var terminalCapabilities: TerminalCapabilities {
        get { self[TerminalCapabilitiesKey.self] }
        set { self[TerminalCapabilitiesKey.self] = newValue }
    }
}
