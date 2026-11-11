//  🖥️ TUI — A Terminal UI framework for Swift
//  AllProgramsSettingsLocation.swift
//
//  Where the person's settings for every TUI program are kept: one file in
//  TUI's own configuration folder, beside each app's, which `TUI_CONFIG_DIR`
//  moves as it moves theirs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Where the person's settings for all TUI programs are kept: `defaults.json`
/// in TUI's own configuration folder (the owner's USET-PLACE, 2026-11-10),
/// placed by the rule each app's own folder is (``ConfigurationFolder``):
///
/// - With `TUI_CONFIG_DIR` set: `$TUI_CONFIG_DIR/TUI/defaults.json`, beside
///   each app's folder there, so the one variable keeps a run off both.
/// - macOS: `~/Library/Application Support/TUI/defaults.json`.
/// - Windows: `%APPDATA%\TUI\defaults.json`.
/// - Elsewhere: `$XDG_CONFIG_HOME/tui/defaults.json`, else
///   `~/.config/tui/defaults.json`: in lower case, as XDG tools name theirs.
package enum AllProgramsSettingsLocation {
    /// The file's name.
    package static let fileName = "defaults.json"

    /// TUI's folder's name on `system`.
    private static func folderName(on system: ConfigurationFolder.System) -> String {
        system == .other ? "tui" : "TUI"
    }

    /// The file for this process.
    package static func file() -> URL {
        ConfigurationFolder.folder(named: folderName(on: .current)).appendingPathComponent(fileName)
    }

    /// The file on `system`, for a process started with `environment` by a
    /// person whose home folder is `home`.
    package static func file(
        on system: ConfigurationFolder.System, environment: [String: String], home: URL
    ) -> URL {
        ConfigurationFolder.folder(named: folderName(on: system), for: system, environment: environment, home: home)
            .appendingPathComponent(fileName)
    }
}
