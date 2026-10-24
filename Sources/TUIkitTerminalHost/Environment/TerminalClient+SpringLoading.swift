//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+SpringLoading.swift
//
//  The host's own spring-loading delay, which a paused drag waits on a
//  spring-loaded control (owner ruling B82).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

extension TerminalClient {
    /// The host's spring-loading delay, or `nil` where there is none to read:
    /// a host with no such setting (Linux, a wasm guest), or one never set.
    ///
    /// On macOS, System Settings ▸ Accessibility ▸ Pointer Control's
    /// spring-loading speed, `com.apple.springing.delay` in the global domain,
    /// in seconds (a float: `defaults read-type -g com.apple.springing.delay`
    /// says so, and reads 0.5 at the default, on macOS 15.8.1). Only worth
    /// asking where ``SessionLocality/isLocal()`` says the user is at this
    /// machine: over ssh it is the server's.
    package static func hostSpringLoadingDelay() -> Duration? {
        #if canImport(Darwin)
            // Another application's preferences are cached in this process;
            // synchronising re-reads them, so a setting changed while the app
            // runs is seen the next time it is asked.
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
            let value = CFPreferencesCopyAppValue("com.apple.springing.delay" as CFString, kCFPreferencesAnyApplication)
            return springLoadingDelay(preferenceValue: value)
        #else
            return nil
        #endif
    }

    /// A delay from the preference's value: a number of seconds, zero or more.
    /// `nil` for anything else.
    static func springLoadingDelay(preferenceValue value: Any?) -> Duration? {
        let seconds: Double? =
            switch value {
            case let number as NSNumber: number.doubleValue
            case let text as String: Double(text)
            default: nil
            }
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return .milliseconds(Int64((seconds * 1000).rounded()))
    }
}
