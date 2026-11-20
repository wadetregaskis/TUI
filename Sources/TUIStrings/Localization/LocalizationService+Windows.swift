//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService+Windows.swift
//
//  The user's languages and locale as Windows keeps them, where Foundation
//  has nothing to read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if os(Windows)
import WinSDK
#endif

extension LocalizationService {
    /// The user's preferred languages as the system keeps them, most preferred
    /// first: on Windows its display languages (Settings ▸ Time & language ▸
    /// Language & region), elsewhere `NSLocale.preferredLanguages`.
    ///
    /// On Windows, Foundation's list is the sentinel `["en-001"]`, as on Linux,
    /// whatever the user chose (Swift 6.3.3, measured 2026-11-20 on a machine
    /// set to `en-US`), and Windows sets none of the POSIX variables, so
    /// without this every Windows user read TUI in English.
    static var systemLanguageList: [String] {
        #if os(Windows)
            windowsPreferredUILanguages ?? NSLocale.preferredLanguages
        #else
            NSLocale.preferredLanguages
        #endif
    }

    /// The user's locale as the system keeps it, for its region: on Windows
    /// the one its regional format names (`GetUserDefaultLocaleName`),
    /// elsewhere `Locale.current`.
    ///
    /// On Windows, Foundation's `Locale.current` is `en_001`, the world region,
    /// whatever the user chose (Swift 6.3.3, measured 2026-11-20 on a machine
    /// set to `en-US`), so dates came out day first for an American.
    static var systemLocale: Locale? {
        #if os(Windows)
            windowsUserLocaleName.map(Locale.init(identifier:)) ?? .current
        #else
            .current
        #endif
    }

    #if os(Windows)
        /// `GetUserPreferredUILanguages`'s list, as BCP-47 tags (`en-US`); `nil`
        /// where it answers nothing.
        private static var windowsPreferredUILanguages: [String]? {
            var count: ULONG = 0
            var size: ULONG = 0
            let flags = DWORD(MUI_LANGUAGE_NAME)
            guard unsafe GetUserPreferredUILanguages(flags, &count, nil, &size), size > 0 else { return nil }
            var buffer = [WCHAR](repeating: 0, count: Int(size))
            guard unsafe GetUserPreferredUILanguages(flags, &count, &buffer, &size) else { return nil }
            return windowsLanguageList(buffer)
        }

        /// `GetUserDefaultLocaleName`'s answer (`en-US`); `nil` where it has none.
        private static var windowsUserLocaleName: String? {
            var buffer = [WCHAR](repeating: 0, count: Int(LOCALE_NAME_MAX_LENGTH))
            guard unsafe GetUserDefaultLocaleName(&buffer, Int32(buffer.count)) > 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        }
    #endif

    /// A Windows multi-string — each name ended by a NUL, the list by a second
    /// — as its names; `nil` where it holds none.
    static func windowsLanguageList(_ units: [UInt16]) -> [String]? {
        let names = units.split(separator: 0).map { String(decoding: $0, as: UTF16.self) }
        return names.isEmpty ? nil : names
    }
}
