//  🖥️ TUI — A Terminal UI framework for Swift
//  SwiftUIKeySpellingTests.swift
//
//  An interpolated key as SwiftUI spells it — `%lld` for an `Int`, `%lf` for a
//  `Double`, a `specifier:` as written — beside TUI's own, which has `%@`
//  for every value, and the lookup that tries SwiftUI's first: a String
//  Catalog extracted from SwiftUI code is keyed SwiftUI's way (deviation T10,
//  closed by the owner's ruling of 2026-10-13). The spellings are SwiftUI's,
//  measured on macOS 15.8 (`Tools/SwiftUIProbes/Localization keys/keys.out`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@Suite("A key as SwiftUI spells it")
struct SwiftUIKeySpellingTests {

    /// One interpolated key, what SwiftUI's key for it is, and a name.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let key: LocalizedStringKey
        let swiftUI: String?
        /// TUI's own key: `%@` for every value.
        var tuikit = "v %@"
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "Int", key: "v \(5)", swiftUI: "v %lld"),
        Case(name: "Int8", key: "v \(Int8(5))", swiftUI: "v %d"),
        Case(name: "Int16", key: "v \(Int16(5))", swiftUI: "v %d"),
        Case(name: "Int32", key: "v \(Int32(5))", swiftUI: "v %d"),
        Case(name: "Int64", key: "v \(Int64(5))", swiftUI: "v %lld"),
        Case(name: "UInt", key: "v \(UInt(5))", swiftUI: "v %llu"),
        Case(name: "UInt8", key: "v \(UInt8(5))", swiftUI: "v %u"),
        Case(name: "UInt16", key: "v \(UInt16(5))", swiftUI: "v %u"),
        Case(name: "UInt32", key: "v \(UInt32(5))", swiftUI: "v %u"),
        Case(name: "UInt64", key: "v \(UInt64(5))", swiftUI: "v %llu"),
        Case(name: "Float", key: "v \(Float(2.5))", swiftUI: "v %f"),
        Case(name: "Double", key: "v \(2.5)", swiftUI: "v %lf"),
        Case(name: "CGFloat", key: "v \(CGFloat(2.5))", swiftUI: "v %lf"),
        Case(name: "an Int's specifier", key: "v \(5, specifier: "%x")", swiftUI: "v %x"),
        Case(name: "a Double's specifier", key: "v \(2.5, specifier: "%.2f")", swiftUI: "v %.2f"),
        Case(name: "a percent beside a number", key: "100% \(5)", swiftUI: "100%% %lld", tuikit: "100%% %@"),
        Case(name: "several", key: "\(5) of \(2.5) and \("x")", swiftUI: "%lld of %lf and %@", tuikit: "%@ of %@ and %@"),
        // SwiftUI's key holds `%@` for each of these, as TUI's does: no
        // second spelling.
        Case(name: "String", key: "v \("x")", swiftUI: nil),
        Case(name: "Substring", key: "v \("xy".dropFirst())", swiftUI: nil),
        Case(name: "AttributedString", key: "v \(AttributedString("a"))", swiftUI: nil),
        Case(name: "NSNumber", key: "v \(NSNumber(value: 3))", swiftUI: nil),
        Case(name: "NSNumber formatter", key: "v \(NSNumber(value: 3), formatter: NumberFormatter())", swiftUI: nil),
        Case(name: "URL (ReferenceConvertible)", key: "v \(URL(string: "https://example.com")!)", swiftUI: nil),
        Case(name: "a format style", key: "v \(2.5, format: .number)", swiftUI: nil),
        Case(name: "no value", key: "plain", swiftUI: nil, tuikit: "plain"),
    ]

    @Test("Each kind of value is spelt as SwiftUI spells it, and TUI's key keeps %@", arguments: cases)
    func spelling(_ testCase: Case) {
        #expect(testCase.key.swiftUIKey == testCase.swiftUI)
        #expect(testCase.key.key == testCase.tuikit)
    }

    @MainActor
    @Test("An interpolated Text is %@ in SwiftUI's key too, so there is no second spelling")
    func interpolatedText() {
        let key: LocalizedStringKey = "v \(Text("t"))"
        #expect(key.swiftUIKey == nil)
        #expect(key.key == "v %@")
    }

    // MARK: - Lookup

    private let configDir = NSTemporaryDirectory() + "tuikit-t10-\(UUID().uuidString)"

    private func service(bundle: Bundle = .main) -> LocalizationService {
        let service = LocalizationService(configDirectoryPath: configDir, defaultBundle: bundle)
        service.pinLanguageForTesting(.english)
        return service
    }

    @Test("A translation keyed as SwiftUI keys it is found")
    func registeredSwiftUIKey() {
        let service = service()
        service.register(translations: ["en": ["Moved %lld rows to %@": "Shifted %lld rows into %@"]])
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.resolved(with: service) == "Shifted 3 rows into Backlog")
    }

    @Test("A table keyed as SwiftUI keys it is found, a specifier's spelling included")
    func tableSwiftUIKey() throws {
        let files = try TableBundle([
            "en": ["Localizable": ["Price %.2f": "Cost: %.2f", "Moved %lld rows to %@": "%lld rows went to %@"]],
            "de": ["Localizable": ["Moved %lld rows to %@": "%lld Zeilen nach %@ verschoben"]],
        ])
        let service = service(bundle: files.bundle)
        let price: LocalizedStringKey = "Price \(2.5, specifier: "%.2f")"
        #expect(price.resolved(with: service) == "Cost: 2.50")
        let moved: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(moved.resolved(with: service) == "3 rows went to Backlog")
        service.pinLanguageForTesting(.german)
        #expect(moved.resolved(with: service) == "3 Zeilen nach Backlog verschoben")
    }

    @Test("SwiftUI's spelling comes first in a language, and TUI's is still found")
    func bothSpellings() {
        let service = service()
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        service.register(translations: ["en": ["Moved %@ rows to %@": "TUI's: %@ to %@"]])
        #expect(key.resolved(with: service) == "TUI's: 3 to Backlog", "a table keyed TUI's way was lost")
        service.register(translations: ["en": ["Moved %lld rows to %@": "SwiftUI's: %lld to %@"]])
        #expect(key.resolved(with: service) == "SwiftUI's: 3 to Backlog")
    }

    @Test("The language comes before the spelling: a German entry keyed TUI's way beats an English one keyed SwiftUI's")
    func languageFirst() {
        let service = service()
        service.register(translations: [
            "en": ["Moved %lld rows to %@": "English: %lld to %@"],
            "de": ["Moved %@ rows to %@": "Deutsch: %@ nach %@"],
        ])
        service.pinLanguageForTesting(.german)
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.resolved(with: service) == "Deutsch: 3 nach Backlog")
    }

    @Test(
        "A registered key is taken for SwiftUI's spelling only if it holds a conversion other than %@ and %%",
        arguments: [
            ("Moved %lld rows to %@", true), ("Price %.2f", true), ("%d", true), ("Moved %1$@", true),
            ("Moved %@ rows to %@", false), ("100%% done", false), ("trailing %", false), ("", false),
            ("stress.scenario.heading", false),
        ])
    func printfConversion(_ key: String, _ holds: Bool) {
        #expect(LocalizationService.holdsPrintfConversion(key) == holds)
    }

    @Test("A key with no entry either way reads as it was written")
    func untranslated() {
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog") at \(2.5, specifier: "%.1f")"
        #expect(key.resolved(with: service()) == "Moved 3 rows to Backlog at 2.5")
    }

    @MainActor
    @Test("Text looks a key up by SwiftUI's spelling too")
    func textUsesIt() {
        // Namespaced to this test; registration is in memory.
        LocalizationService.shared.register(translations: ["en": ["test.t10 moved %lld": "test.t10 shifted %lld"]])
        #expect(Text("test.t10 moved \(4)").content == "test.t10 shifted 4")
    }
}
