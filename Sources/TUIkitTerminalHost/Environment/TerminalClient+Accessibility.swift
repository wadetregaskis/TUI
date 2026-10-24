//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+Accessibility.swift
//
//  The accessibility preferences TUIkit reads from where the app runs: the
//  user's `TUIKIT_*` variables, and the host's own settings.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - The preferences

/// The accessibility preferences TUIkit reads from the user and the host, as a
/// set: what the app runner hands its render loop, which writes each into the
/// root of every frame's environment.
package struct AccessibilityPreferences: OptionSet, Sendable, Hashable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Less motion: ``EnvironmentValues/accessibilityReduceMotion``.
    package static let reduceMotion = Self(rawValue: 1 << 0)

    /// Less transparency: `accessibilityReduceTransparency`.
    package static let reduceTransparency = Self(rawValue: 1 << 1)

    /// Cues that do not rest on colour alone: `accessibilityDifferentiateWithoutColor`.
    package static let differentiateWithoutColor = Self(rawValue: 1 << 2)

    /// More contrast: `colorSchemeContrast` answers `.increased`.
    package static let increaseContrast = Self(rawValue: 1 << 3)

    /// Each preference, the `TUIKIT_*` variable that asks for it, and the
    /// `com.apple.universalaccess` key that is macOS's setting for it.
    static let named: [(preference: Self, variable: String, macOSKey: String)] = [
        (.reduceMotion, "TUIKIT_REDUCE_MOTION", "reduceMotion"),
        (.reduceTransparency, "TUIKIT_REDUCE_TRANSPARENCY", "reduceTransparency"),
        (.differentiateWithoutColor, "TUIKIT_DIFFERENTIATE_WITHOUT_COLOR", "differentiateWithoutColor"),
        (.increaseContrast, "TUIKIT_INCREASE_CONTRAST", "increaseContrast"),
    ]
}

// MARK: - The user's setting

extension TerminalClient {
    /// Whether the user asked for less motion: `TUIKIT_REDUCE_MOTION=1` in
    /// the environment the app was started in. Read once, at first use.
    ///
    /// The app runner hands it to its render loop, which writes it into the
    /// root of every frame's environment, as
    /// ``EnvironmentValues/accessibilityReduceMotion``, before the scene's own
    /// `.reduceMotion(_:)`. Only the app runner reads it: a headless app's
    /// loop, and every test's, draws as if it were unset.
    public static let reduceMotionRequested: Bool =
        reduceMotionRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``reduceMotionRequested``, posed on its input so it can
    /// be asked without changing what a whole process reads.
    static func reduceMotionRequested(environment: [String: String]) -> Bool {
        environment["TUIKIT_REDUCE_MOTION"] == "1"
    }

    /// Every preference the user asked for in the environment the app was
    /// started in, each with its variable set to `1`, as
    /// ``reduceMotionRequested`` reads its one: `TUIKIT_REDUCE_MOTION`,
    /// `TUIKIT_REDUCE_TRANSPARENCY`, `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR` and
    /// `TUIKIT_INCREASE_CONTRAST`. Read once, at first use; only the app
    /// runner reads it.
    package static let accessibilityRequested: AccessibilityPreferences =
        accessibilityRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``accessibilityRequested``, posed on its input.
    static func accessibilityRequested(environment: [String: String]) -> AccessibilityPreferences {
        AccessibilityPreferences.named.reduce(into: []) { asked, named in
            if environment[named.variable] == "1" { asked.insert(named.preference) }
        }
    }
}

// MARK: - The host's setting

extension TerminalClient {
    /// The host's own accessibility settings, or `nil` where there are none to
    /// read: another desktop, no `gsettings`, a wasm guest.
    ///
    /// On macOS, System Settings ▸ Accessibility ▸ Display's Reduce motion,
    /// Reduce transparency, Differentiate without colour and Increase
    /// contrast: the `com.apple.universalaccess` keys
    /// ``AccessibilityPreferences`` names. On GNOME, animations switched off
    /// (`org.gnome.desktop.interface enable-animations`) and high contrast
    /// (`org.gnome.desktop.a11y.interface high-contrast`); GNOME has no
    /// setting for the other two.
    ///
    /// Only worth asking where ``SessionLocality/isLocal()`` says the user is at
    /// this machine: over ssh they are the server's settings. Blocking — on
    /// Linux it runs `gsettings` (``TerminalHost/runBounded(_:)``) — so the app
    /// runner asks it off the main actor, at launch and whenever the terminal
    /// regains the focus.
    package static func hostAccessibility() -> AccessibilityPreferences? {
        #if canImport(Darwin)
            let domain = "com.apple.universalaccess" as CFString
            // Another application's preferences are cached in this process;
            // synchronising re-reads them, so a setting changed while the app
            // runs is seen the next time it is asked.
            CFPreferencesAppSynchronize(domain)
            return AccessibilityPreferences.named.reduce(into: []) { on, named in
                // An unset key is the setting at its default: off.
                if CFPreferencesCopyAppValue(named.macOSKey as CFString, domain) as? Bool == true {
                    on.insert(named.preference)
                }
            }
        #else
            let reducesMotion = gnomeReducesMotion(
                gsettingsOutput: TerminalHost.runBounded(
                    ["gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]))
            let highContrast = gnomeSwitch(
                gsettingsOutput: TerminalHost.runBounded(
                    ["gsettings", "get", "org.gnome.desktop.a11y.interface", "high-contrast"]))
            guard reducesMotion != nil || highContrast != nil else { return nil }
            var on: AccessibilityPreferences = []
            if reducesMotion == true { on.insert(.reduceMotion) }
            if highContrast == true { on.insert(.increaseContrast) }
            return on
        #endif
    }

    /// GNOME's answer, from what `gsettings get org.gnome.desktop.interface
    /// enable-animations` printed: animations off is reduced motion. `nil`
    /// when it printed neither `true` nor `false`, or could not be run.
    static func gnomeReducesMotion(gsettingsOutput: String?) -> Bool? {
        gnomeSwitch(gsettingsOutput: gsettingsOutput).map { !$0 }
    }

    /// A GNOME boolean setting, from what `gsettings get` printed: `nil` when it
    /// printed neither `true` nor `false` (no such schema or key), or could not
    /// be run.
    static func gnomeSwitch(gsettingsOutput: String?) -> Bool? {
        switch gsettingsOutput?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": true
        case "false": false
        default: nil
        }
    }
}
