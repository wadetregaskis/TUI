//  🖥️ TUI — A Terminal UI framework for Swift
//  FileNameRules.swift
//
//  What a file system refuses in one file's name.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a file's name cannot be, where TUI makes one from what was typed or
/// given: a save panel's name, a new folder's, a settings file's suite.
///
/// Everywhere: empty, `.` or `..`, or a `/`, which names a folder. On Windows,
/// besides, what its file systems refuse or read as something else: a
/// character of `<>:"/\|?*` or a control character (a `:` names an alternate
/// data stream of the file before it, so `notes:old` wrote a hidden stream of
/// `notes` and reported success; a `\` names a folder), a name ending in a dot
/// or a space, which Windows drops, and a device's name — `CON`, `PRN`, `AUX`,
/// `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, `CONIN$`, `CONOUT$` — with or
/// without an extension.
package enum FileNameRules {
    /// Whether `name` is one no file on this platform can have.
    package static func refuses(_ name: String) -> Bool {
        #if os(Windows)
            refuses(name, onWindows: true)
        #else
            refuses(name, onWindows: false)
        #endif
    }

    /// Whether `name` is one no file can have, under Windows's rules or every
    /// other platform's: the rule behind ``refuses(_:)``, posed on its input.
    package static func refuses(_ name: String, onWindows: Bool) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return true }
        guard onWindows else { return false }
        if name.contains(where: isForbiddenOnWindows) || name.hasSuffix(".") || name.hasSuffix(" ") { return true }
        let stem = name.prefix { $0 != "." }.uppercased()
        return windowsDeviceNames.contains(stem)
    }

    /// Whether `character` cannot be in a file's name on Windows: one of
    /// `<>:"/\|?*`, or a control character.
    package static func isForbiddenOnWindows(_ character: Character) -> Bool {
        #"<>:"/\|?*"#.contains(character) || character.asciiValue.map { $0 < 32 } == true
    }

    /// The names Windows keeps for devices, in any letter case and with any
    /// extension: `con.txt` opens the console.
    private static let windowsDeviceNames: Set<String> = Set(
        ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]
            + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })
}
