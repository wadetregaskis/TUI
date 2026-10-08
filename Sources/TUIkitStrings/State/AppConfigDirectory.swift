//  🖥️ TUIkit — Terminal UI Kit for Swift
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
func sanitizedProcessName(_ name: String) -> String {
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
/// name, in the conventional per-platform location:
/// - **macOS**: `~/Library/Application Support/<appName>`
/// - **Linux / other**: `$XDG_CONFIG_HOME/<appName>`, falling back to
///   `~/.config/<appName>` (XDG Base Directory convention).
///
/// Shared by `@AppStorage`'s file backend (`JSONFileStorage`) and
/// `LocalizationService`, so all of an app's persisted configuration lives in
/// one place rather than scattered across directories.
func appConfigDirectory() -> URL {
    let appName = sanitizedProcessName(ProcessInfo.processInfo.processName)

    // Explicit override — the isolation hook for anything driving a TUIkit
    // app that must not touch the real per-app state (a PTY test harness,
    // CI). It matters most on Apple platforms, where BOTH the default
    // storage (UserDefaults) and the idiomatic directory below resolve
    // through the real user home and ignore a `$HOME` override — a
    // "sandboxed" run would otherwise read and write the developer's own
    // preferences. Setting it also switches `@AppStorage` to file-backed
    // storage under this directory (see ``StorageDefaults/backend``).
    if let override = ProcessInfo.processInfo.environment["TUIKIT_CONFIG_DIR"],
        !override.isEmpty
    {
        return URL(fileURLWithPath: override).appendingPathComponent(appName)
    }

    #if os(macOS)
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName)
    #else
        if let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
            return URL(fileURLWithPath: xdgConfig)
                .appendingPathComponent(appName)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent(appName)
    #endif
}
