//  🖥️ TUI — A Terminal UI framework for Swift
//  AppConfigDirectory.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Process Name Sanitization

/// Sanitizes a process name for safe use as a file system path component.
///
/// Removes characters that could cause path traversal or file system issues:
/// - Forward slashes (`/`)
/// - Null bytes (`\0`)
/// - Replaces `..` sequences (path traversal)
///
/// Falls back to `"app"` if the result is empty after sanitization.
///
/// - Parameter name: The raw process name.
/// - Returns: A sanitized string safe for use as a directory name.
///
/// `package` for TUIFoundation's tests, which check it directly.
package func sanitizedProcessName(_ name: String) -> String {
    var sanitized =
        name
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "\0", with: "")
        .replacingOccurrences(of: "..", with: "")
    sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "app" : sanitized
}

// MARK: - Config Directory

/// Returns the app-specific, platform-idiomatic configuration directory.
///
/// Each executable gets its own directory, named after the sanitized process
/// name, in the conventional per-platform location (``ConfigurationFolder``):
/// - **macOS**: `~/Library/Application Support/<appName>`
/// - **Windows**: `%APPDATA%\<appName>`
/// - **Linux / other**: `$XDG_CONFIG_HOME/<appName>`, falling back to
///   `~/.config/<appName>` (XDG Base Directory convention).
///
/// Shared by `@AppStorage`'s file backend (`JSONFileStorage`), Linux's
/// `UserDefaultsStorage` and `LocalizationService`, so all of an app's
/// persisted configuration lives in one place rather than scattered across
/// directories.
package func appConfigDirectory() -> URL {
    ConfigurationFolder.folder(named: sanitizedProcessName(ProcessInfo.processInfo.processName))
}

// MARK: - Where a Configuration Folder Goes

/// Where a configuration folder goes on each system: an app's own
/// (``appConfigDirectory()``) and TUI's, which holds the person's settings for
/// every program (``AllProgramsSettingsLocation``). One rule for both, so
/// `TUI_CONFIG_DIR` moves both alike.
///
/// Every system's rule is here, chosen by an argument rather than by `#if`
/// alone, so each is tested on any machine and a Windows build compiles the
/// code it runs.
package enum ConfigurationFolder {
    /// The systems whose places differ.
    package enum System: Sendable {
        case macOS
        case windows
        /// Linux and every other system, by the XDG Base Directory convention.
        case other

        /// The system this is built for.
        package static var current: Self {
            #if os(macOS)
                .macOS
            #elseif os(Windows)
                .windows
            #else
                .other
            #endif
        }
    }

    /// The folder `name` in this process's place for configuration.
    package static func folder(named name: String) -> URL {
        var applicationSupport: URL?
        #if os(macOS)
            // Foundation's answer, which a sandboxed app's container moves.
            applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        return folder(
            named: name, for: .current, environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser, applicationSupport: applicationSupport)
    }

    /// The folder `name` on `system`, for a process started with `environment`
    /// by a person whose home folder is `home`:
    ///
    /// - With `TUI_CONFIG_DIR` set, on every system: `$TUI_CONFIG_DIR/<name>`.
    ///   The isolation hook for anything driving a TUI app that must not touch
    ///   the real state (a PTY test harness, CI). It matters most on Apple
    ///   platforms, where BOTH the default storage (UserDefaults) and the
    ///   idiomatic directory resolve through the real user home and ignore a
    ///   `$HOME` override — a "sandboxed" run would otherwise read and write
    ///   the developer's own preferences. Setting it also switches
    ///   `@AppStorage` to file-backed storage under it (see
    ///   `StorageDefaults.backend`).
    /// - macOS: `<applicationSupport>/<name>`, Foundation's Application
    ///   Support folder, else `~/Library/Application Support/<name>`.
    /// - Windows: `%APPDATA%\<name>`, else `<home>\AppData\Roaming\<name>`.
    /// - Elsewhere: `$XDG_CONFIG_HOME/<name>`, else `~/.config/<name>`.
    package static func folder(
        named name: String, for system: System, environment: [String: String], home: URL,
        applicationSupport: URL? = nil
    ) -> URL {
        if let override = environment["TUI_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        }
        let base: URL
        switch system {
        case .macOS:
            base = applicationSupport ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        case .windows:
            if let appData = environment["APPDATA"], !appData.isEmpty {
                base = URL(fileURLWithPath: appData, isDirectory: true)
            } else {
                base = home.appendingPathComponent("AppData/Roaming", isDirectory: true)
            }
        case .other:
            if let xdgConfig = environment["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
                base = URL(fileURLWithPath: xdgConfig, isDirectory: true)
            } else {
                base = home.appendingPathComponent(".config", isDirectory: true)
            }
        }
        return base.appendingPathComponent(name, isDirectory: true)
    }
}
