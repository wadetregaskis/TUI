//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService+Files.swift
//
//  The files a LocalizationService reads: TUI's own translations, and the
//  language a user chose, where it was stored.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

extension LocalizationService {
    /// Loads TUI's translations into `language` from the JSON file in
    /// ``resources``; `nil` where there is no such file, or it cannot be read.
    func loadTranslationsFromBundle(language: String) -> [String: String]? {
        guard let url = resources.url(named: language, extension: "json", subdirectory: "translations"),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return Self.translationTable(from: data)
    }

    /// A translation file's table — a JSON object of strings — or `nil` where
    /// `data` is not one. The one parser for the bundled files and for the
    /// English compiled in (``builtInEnglish``).
    static func translationTable(from data: Data) -> [String: String]? {
        do {
            return try JSONSerialization.jsonObject(
                with: data,
                options: .fragmentsAllowed
            ) as? [String: String]
        } catch {
            return nil
        }
    }

    /// Loads stored language preference from the default config file.
    static func loadLanguagePreference() -> Language? {
        loadLanguagePreference(from: defaultConfigDirectoryPath())
    }

    /// Loads stored language preference from a specific config directory.
    static func loadLanguagePreference(from configDirectory: String) -> Language? {
        let path = (configDirectory as NSString).appendingPathComponent("language")
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return Language(rawValue: content)
        } catch {
            return nil
        }
    }

    /// The default config directory for the language preference.
    ///
    /// This is the app-specific, platform-idiomatic directory shared with
    /// `@AppStorage` (see `appConfigDirectory()`): `~/Library/Application
    /// Support/<App>` on macOS, `$XDG_CONFIG_HOME/<App>` (else `~/.config/<App>`)
    /// elsewhere. Per-app, so the language preference lives alongside the app's
    /// other settings and no longer leaks between TUI apps.
    static func defaultConfigDirectoryPath() -> String {
        appConfigDirectory().path
    }
}
