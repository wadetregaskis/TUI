//  🖥️ TUI — A Terminal UI framework for Swift
//  ResolvedStringsTests.swift
//
//  The localization service remembers what it resolved, and forgets it the
//  moment an answer could change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@MainActor
@Suite("Resolved localized strings")
struct ResolvedStringsTests {
    private func service() -> (LocalizationService, String) {
        let directory = NSTemporaryDirectory() + "tuikit-resolved-\(UUID().uuidString)"
        let service = LocalizationService(configDirectoryPath: directory)
        service.pinLanguageForTesting(.english)
        return (service, directory)
    }

    @Test("A key nobody translates, then translated, reads the translation at once")
    func registrationIsSeen() {
        let (service, directory) = service()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(service.string(for: "resolved.greeting", tableName: nil, bundle: nil) == "resolved.greeting")
        service.registerWithoutRendering(translations: ["en": ["resolved.greeting": "Hello"]])
        #expect(service.string(for: "resolved.greeting", tableName: nil, bundle: nil) == "Hello")
    }

    @Test("A change of language reads the new language's word at once")
    func languageIsSeen() {
        let (service, directory) = service()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        service.registerWithoutRendering(translations: [
            "en": ["resolved.yes": "Yes"], "de": ["resolved.yes": "Ja"],
        ])
        #expect(service.string(for: "resolved.yes", tableName: nil, bundle: nil) == "Yes")
        service.setLanguageWithoutRendering(.german)
        #expect(service.string(for: "resolved.yes", tableName: nil, bundle: nil) == "Ja")
    }

    @Test("The memo keeps two generations, and a full one turns over rather than growing")
    func bounded() {
        var memo = ResolvedStrings()
        func key(_ index: Int) -> ResolvedStrings.Key {
            ResolvedStrings.Key(key: "k\(index)", swiftUIKey: nil, tableName: nil, bundle: nil)
        }
        for index in 0..<(ResolvedStrings.limit * 2) { memo.remember("v\(index)", for: key(index)) }
        #expect(memo.answer(for: key(0)) == "v0", "the previous generation still answers")
        memo.remember("new", for: key(-1))
        #expect(memo.answer(for: key(0)) == nil, "a turnover forgets the oldest generation")
        #expect(memo.answer(for: key(ResolvedStrings.limit * 2 - 1)) != nil)
    }
}
