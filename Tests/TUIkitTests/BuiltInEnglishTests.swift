//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BuiltInEnglishTests.swift
//
//  TUIkit's English words are compiled in as well as bundled, for a program
//  shipped without its resource bundle. The copy must be the file, and a
//  service with no bundle must read it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStrings

@Suite("Built-in English")
struct BuiltInEnglishTests {

    /// The file the copy is of, in the source tree.
    private static let englishFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TUIkitTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/TUIkitStrings/Localization/translations/en.json")

    /// A config directory of the test's own, so no service here reads or
    /// writes a real language preference.
    private static func scratchConfigDirectory() -> String {
        NSTemporaryDirectory() + "tuikit-builtin-english-\(UUID().uuidString)"
    }

    @Test("The compiled-in English is en.json, key for key")
    func copyIsTheFile() throws {
        let data = try Data(contentsOf: Self.englishFile)
        let file = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        let copy = LocalizationService.builtInEnglish
        let missing = Set(file.keys).subtracting(copy.keys).sorted()
        let extra = Set(copy.keys).subtracting(file.keys).sorted()
        let differing = file.keys.filter { copy[$0] != nil && copy[$0] != file[$0] }.sorted()
        #expect(
            missing.isEmpty && extra.isEmpty && differing.isEmpty,
            """
            LocalizationService+BuiltInEnglish.swift is not a copy of en.json — \
            missing: \(missing); extra: \(extra); differing: \(differing). \
            Paste en.json between its #\"\"\" delimiters.
            """)
        #expect(!copy.isEmpty)
    }

    @Test("Without its resource bundle, TUIkit's words read in English")
    func noBundleReadsEnglish() {
        let directory = Self.scratchConfigDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let service = LocalizationService(configDirectoryPath: directory, resources: .absent)
        #expect(service.frameworkString(for: "statusbar.quit") == "quit")
        #expect(service.string(for: "button.cancel") == "Cancel")
    }

    @Test("Without its resource bundle, a German user reads English, not keys")
    func noBundleGermanReadsEnglish() {
        let directory = Self.scratchConfigDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let german = ["LANG": "de_DE.UTF-8"]
        // The same environment WITH the bundle reads German: what makes the
        // English below the fallback rather than a language never asked for.
        let bundled = LocalizationService(configDirectoryPath: directory, environment: german)
        #expect(bundled.currentLanguage == .german)
        #expect(bundled.frameworkString(for: "statusbar.quit") == "beenden")

        let bare = LocalizationService(configDirectoryPath: directory, environment: german, resources: .absent)
        #expect(bare.currentLanguage == .german)
        #expect(bare.frameworkString(for: "statusbar.quit") == "quit")
        #expect(bare.string(for: "button.cancel") == "Cancel")
    }

    @Test("A key TUIkit does not have still reads as itself")
    func unknownKeyIsItself() {
        let directory = Self.scratchConfigDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let service = LocalizationService(configDirectoryPath: directory, resources: .absent)
        #expect(service.string(for: "no.such.key") == "no.such.key")
    }
}
