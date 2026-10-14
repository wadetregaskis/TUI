//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+ReduceMotion.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

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
}

// MARK: - The host's setting

extension TerminalClient {
    /// Whether the machine this app runs on has its own Reduce Motion on —
    /// macOS's (System Settings ▸ Accessibility ▸ Display ▸ Reduce motion), or
    /// GNOME's animations switched off (`org.gnome.desktop.interface
    /// enable-animations`) — or `nil` where there is no such setting to read:
    /// another desktop, no `gsettings`, a wasm guest.
    ///
    /// Only worth asking where ``SessionLocality/isLocal()`` says the user is at
    /// this machine: over ssh it is the server's setting. Blocking — on Linux
    /// it runs `gsettings` (``TerminalHost/runBounded(_:)``) — so the app
    /// runner asks it off the main actor, at launch and whenever the terminal
    /// regains the focus.
    package static func hostReducesMotion() -> Bool? {
        #if canImport(Darwin)
            let domain = "com.apple.universalaccess" as CFString
            // Another application's preferences are cached in this process;
            // synchronising re-reads them, so a setting changed while the app
            // runs is seen the next time it is asked.
            CFPreferencesAppSynchronize(domain)
            // An unset key is the setting at its default: off.
            return CFPreferencesCopyAppValue("reduceMotion" as CFString, domain) as? Bool ?? false
        #else
            return gnomeReducesMotion(
                gsettingsOutput: TerminalHost.runBounded(
                    ["gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]))
        #endif
    }

    /// GNOME's answer, from what `gsettings get org.gnome.desktop.interface
    /// enable-animations` printed: animations off is reduced motion. `nil`
    /// when it printed neither `true` nor `false`, or could not be run.
    static func gnomeReducesMotion(gsettingsOutput: String?) -> Bool? {
        switch gsettingsOutput?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "false": true
        case "true": false
        default: nil
        }
    }
}
