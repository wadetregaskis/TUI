//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilitiesEnvironment.swift
//
//  `\.terminalCapabilities`, the colour depth beside it, and the keyboard
//  features the kitty keyboard protocol's negotiation settles.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling
import TUITerminalHost

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

extension KeyboardReporting {
    /// What `capabilities` says the terminal reports: each keyboard feature
    /// it supports `true`, an unsupported or undetermined one `false`, as a
    /// terminal TUI never asked reads (``legacy``). The way back from
    /// ``TerminalCapabilities/keyboard(_:)``, for a public API that takes the
    /// app's `\.terminalCapabilities`.
    package init(_ capabilities: TerminalCapabilities) {
        isEnhanced = capabilities.supportsAny(of: TerminalCapabilities.negotiatedKeyboard)
        disambiguatesKeys = capabilities.supports(.disambiguatedKeys)
        reportsShiftedKeys = capabilities.supports(.shiftedKeys)
        reportsRepeats = capabilities.supports(.keyRepeats)
        reportsReleases = capabilities.supports(.keyReleases)
        reportsModifierKeys = capabilities.supports(.modifierKeys)
        reportsLockStates = capabilities.supports(.capsLock)
        reportsNumericPad = capabilities.supports(.numericPad)
    }
}

// MARK: - Environment key

private struct TerminalCapabilitiesKey: EnvironmentKey {
    /// A view rendered outside a running app has no terminal behind it to ask.
    static let defaultValue = TerminalCapabilities.nothingKnown
}

extension EnvironmentValues {
    /// What the terminal painting the app can do, feature by feature, as far
    /// as TUI knows — see ``TerminalCapabilities``.
    ///
    /// Published by the run loop: at launch from TUI's tables and the
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
