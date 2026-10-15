//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BundleStringTableTests.swift
//
//  A key is read from the app's own string table through Foundation —
//  `Localizable` in the main bundle unless `Text(_:tableName:bundle:comment:)`
//  names another — beside TUIkit's dictionaries, in the app's language first.
//  The bundles are written to a temporary directory, as `.lproj` folders of
//  `.strings` files, which Foundation reads on Linux as on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

/// A bundle of `.lproj` folders in a temporary directory, removed with it.
final class TableBundle {
    let path: String
    let bundle: Bundle

    /// `tables` maps an `.lproj` name to the tables in it, each a dictionary.
    init(_ tables: [String: [String: [String: String]]]) throws {
        path = NSTemporaryDirectory() + "tuikit-tables-\(UUID().uuidString)"
        let manager = FileManager.default
        for (localization, files) in tables {
            let folder = (path as NSString).appendingPathComponent("\(localization).lproj")
            try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for (table, entries) in files {
                let text = entries.sorted { $0.key < $1.key }
                    .map { "\"\($0.key)\" = \"\($0.value)\";" }
                    .joined(separator: "\n")
                try text.write(
                    toFile: (folder as NSString).appendingPathComponent("\(table).strings"),
                    atomically: true, encoding: .utf8)
            }
        }
        bundle = try #require(Bundle(path: path))
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}

@MainActor
@Suite("String tables in a bundle")
final class BundleStringTableTests {
    let configDir = NSTemporaryDirectory() + "tuikit-loc-\(UUID().uuidString)"

    deinit {
        try? FileManager.default.removeItem(atPath: configDir)
    }

    private func tables() throws -> TableBundle {
        try TableBundle([
            "en": [
                "Localizable": ["greeting": "Hello", "only.english": "English only", "same": "Okay"],
                "Onboarding": ["welcome": "Welcome aboard"],
            ],
            "de": [
                "Localizable": ["greeting": "Hallo", "same": "OK"],
                "Onboarding": ["welcome": "Willkommen an Bord"],
            ],
            "zh-Hans": ["Localizable": ["greeting": "你好"]],
        ])
    }

    @Test("A key the dictionaries miss is read from the default bundle's Localizable table, in the app's language")
    func theDefaultTableInTheAppsLanguage() throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.english)
        #expect(service.string(for: "greeting") == "Hello")
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: "greeting") == "Hallo", "the table is not read in the app's language")
        service.pinLanguageForTesting(.simplifiedChinese)
        #expect(service.string(for: "greeting") == "你好", "zh did not find zh-Hans.lproj")
    }

    @Test("A key the language's table lacks falls back to English's, and a translation equal to its key counts")
    func fallsBackToEnglish() throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: "only.english") == "English only")
        #expect(service.string(for: "same") == "OK", "German's OK was taken for a miss")
        #expect(service.string(for: "nowhere") == "nowhere")
    }

    @Test("Within a language the app's strings come first: what it registered, then its table, then TUIkit's own")
    func theAppsStringsComeFirst() throws {
        let files = try TableBundle(["en": ["Localizable": ["button.ok": "Table OK", "greeting": "Hello"]]])
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.english)
        #expect(service.string(for: "button.ok") == "Table OK", "TUIkit's own string beat the app's table")
        #expect(service.string(for: "button.cancel") == "Cancel", "TUIkit's own strings are still read")
        service.register(translations: ["en": ["greeting": "Registered hello"]])
        #expect(service.string(for: "greeting") == "Registered hello")
    }

    /// The review's case: English everywhere first meant a key registered in
    /// English never reached the app's own German table.
    @Test("The app's language comes before English, whichever kind of string holds each")
    func theLanguageComesFirst() throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.register(translations: ["en": ["greeting": "Registered hello"]])
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: "greeting") == "Hallo", "the English dictionary beat the German table")
        service.pinLanguageForTesting(.english)
        #expect(service.string(for: "greeting") == "Registered hello")
    }

    @Test("A table the call names is asked before the dictionaries")
    func aNamedTableComesFirst() throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.english)
        service.register(translations: ["en": ["welcome": "Registered welcome"]])
        #expect(service.string(for: "welcome", tableName: "Onboarding", bundle: files.bundle) == "Welcome aboard")
        #expect(service.string(for: "welcome") == "Registered welcome", "the registered string is lost elsewhere")
    }

    @Test("A table and a bundle named by Text are read for its key")
    func textNamesATableAndABundle() throws {
        let files = try tables()
        let shared = LocalizationService.shared
        shared.pinLanguageForTesting(.english)
        #expect(Text("welcome", tableName: "Onboarding", bundle: files.bundle).content == "Welcome aboard")
        #expect(Text("greeting", bundle: files.bundle).content == "Hello", "a bundle named without a table did not read its Localizable")
        #expect(Text("welcome", bundle: files.bundle).content == "welcome", "a key was found outside its table")
        #expect(Text(verbatim: "greeting").content == "greeting")
    }

    @Test("The answers kept for keys made at run time are bounded")
    func theAnswersAreBounded() throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.english)
        for index in 0..<(BundleStringTables.answerLimit + 100) {
            _ = service.string(for: "row.\(index)")
        }
        // English's answers and the fallback's, each at most two generations.
        #expect(service.keptTableAnswerCount <= 4 * BundleStringTables.answerLimit)
        #expect(service.string(for: "greeting") == "Hello", "a forgotten answer is not read again")
    }

    /// The flat cap's failure: a map emptied when it fills served nothing to
    /// a set of keys one larger than it, asked for round after round — every
    /// round filled it, emptied it at the last key and read every key again.
    /// And the same failure moved (the follow-ups lane's review): with an
    /// answer found in the previous generation copied back into the current
    /// one, a set twice the limit read nearly every key again each round
    /// (8,190 of 8,192), though two generations hold all of it.
    @Test(
        "A set of keys over one generation, asked for again and again, is still served from what was kept",
        arguments: [BundleStringTables.answerLimit + 1, 2 * BundleStringTables.answerLimit])
    func aWorkingSetOverAGenerationStillHits(count: Int) throws {
        let files = try tables()
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle)
        service.pinLanguageForTesting(.english)
        let keys = (0..<count).map { "row.\($0)" }
        for key in keys { _ = service.string(for: key) }
        let afterFirstRound = service.tableReadCount
        // English's .lproj and then the fallback, once each for every key.
        #expect(afterFirstRound == 2 * keys.count)
        for _ in 0..<3 {
            for key in keys { _ = service.string(for: key) }
        }
        #expect(service.tableReadCount == afterFirstRound, "a kept answer was read from Foundation again")
        #expect(service.keptTableAnswerCount <= 4 * BundleStringTables.answerLimit)
    }

    @Test("An interpolated key is read from the table and filled in")
    func anInterpolatedKey() throws {
        let files = try TableBundle(["en": ["Localizable": ["Moved %@ rows": "Shifted %@ rows"]]])
        let shared = LocalizationService.shared
        shared.pinLanguageForTesting(.english)
        let count = 3
        #expect(Text("Moved \(count) rows", bundle: files.bundle).content == "Shifted 3 rows")
    }
}
