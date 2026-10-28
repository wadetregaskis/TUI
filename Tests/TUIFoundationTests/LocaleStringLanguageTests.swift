//  🖥️ TUI — A Terminal UI framework for Swift
//  LocaleStringLanguageTests.swift
//
//  `\.locale` picks the language of the strings below it, as SwiftUI's does
//  (the owner's option B, 2026-10-15; measured on macOS 15, 2026-10-18): a
//  `Text` made from a key reads it again, when it is drawn, in the language a
//  subtree's `\.locale` names.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@MainActor
@Suite("A locale override picks the string language", .rendersEnglishUI)
struct LocaleStringLanguageTests {
    init() {
        // Keys of this suite's own, so no other suite reads them.
        LocalizationService.shared.registerWithoutRendering(translations: [
            "en": [
                "test.localeLanguage.greeting": "Hello", "test.localeLanguage.onlyEnglish": "English only",
                "test.localeLanguage.named %@": "Hello, %@",
            ],
            "de": [
                "test.localeLanguage.greeting": "Hallo", "test.localeLanguage.bold": "**Fett** gedruckt",
                "test.localeLanguage.named %@": "Hallo, %@",
            ],
            "fr": ["test.localeLanguage.greeting": "Bonjour"],
        ])
    }

    private func drawn(_ view: some View, width: Int = 30) -> String {
        let context = makeBareRenderContext(width: width, height: 3)
        return renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("With no override a key is read in the app's language")
    func noOverride() {
        #expect(drawn(Text("test.localeLanguage.greeting")).contains("Hello"))
    }

    @Test("An override reads the key in the locale's language, region or not")
    func overrideReadsTheLanguage() {
        let german = Text("test.localeLanguage.greeting").environment(\.locale, Locale(identifier: "de_CH"))
        #expect(drawn(german).contains("Hallo"), "\(drawn(german))")
        let french = Text("test.localeLanguage.greeting").environment(\.locale, Locale(identifier: "fr"))
        #expect(drawn(french).contains("Bonjour"), "\(drawn(french))")
    }

    @Test("A text made before the override is set, or inside a view below it, reads alike")
    func throughAContainer() {
        let view = VStack {
            Text("test.localeLanguage.greeting")
            Text("test.localeLanguage.greeting").bold()
        }
        .environment(\.locale, Locale(identifier: "de"))
        let lines = drawn(view).split(separator: "\n").map(String.init)
        #expect(lines.prefix(2).allSatisfy { $0.contains("Hallo") }, "\(lines)")
    }

    @Test("A language with no strings reads English, as SwiftUI's development language does")
    func unlocalizedLanguage() {
        let view = Text("test.localeLanguage.greeting").environment(\.locale, Locale(identifier: "pt_BR"))
        #expect(drawn(view).contains("Hello"), "\(drawn(view))")
    }

    @Test("A key the language's table lacks reads English rather than the key")
    func missingKeyFallsBackToEnglish() {
        // SwiftUI shows the key here (Deliberate deviations E4).
        let view = Text("test.localeLanguage.onlyEnglish").environment(\.locale, Locale(identifier: "de"))
        #expect(drawn(view).contains("English only"), "\(drawn(view))")
    }

    @Test("TUI's own words read through a key follow the override too")
    func frameworkWords() {
        let english = drawn(Text("button.cancel"))
        let german = drawn(Text("button.cancel").environment(\.locale, Locale(identifier: "de")))
        #expect(english.contains("Cancel"), "\(english)")
        #expect(german.contains("Abbrechen"), "\(german)")
    }

    @Test("A typed key of TUI's, and the view of one, follow the override too")
    func typedFrameworkKeys() {
        let text = drawn(Text(localized: LocalizationKey.Button.cancel).environment(\.locale, Locale(identifier: "de")))
        #expect(text.contains("Abbrechen"), "\(text)")
        let view = drawn(LocalizedString(LocalizationKey.Button.cancel).environment(\.locale, Locale(identifier: "de")))
        #expect(view.contains("Abbrechen"), "\(view)")
        let english = drawn(Text(localized: LocalizationKey.Button.cancel).bold())
        #expect(english.contains("Cancel"), "\(english)")
    }

    @Test("The re-read key draws its Markdown, and the text's own style stays")
    func markdownAndStyle() {
        let context = makeBareRenderContext(width: 30, height: 3)
        let view = Text("test.localeLanguage.bold").italic().environment(\.locale, Locale(identifier: "de"))
        let line = renderToBuffer(view, context: context).lines[0]
        #expect(line.stripped.hasPrefix("Fett gedruckt"), "\(line.stripped)")
        let bold = /\u{1B}\[(?:[0-9;]*;)?1(?:;[0-9;]*)?m/
        let italic = /\u{1B}\[(?:[0-9;]*;)?3(?:;[0-9;]*)?m/
        #expect(line.contains(bold) && line.contains(italic), "\(line)")
    }

    @Test("Two texts made from one key hold the same source, so the memos see them equal")
    func internedSource() throws {
        let first = try #require(Text("test.localeLanguage.greeting").localization)
        let second = try #require(Text("test.localeLanguage.greeting").localization)
        #expect(first === second)
        #expect(Text(verbatim: "plain").localization == nil)
        let one = Text("test.localeLanguage.greeting")
        let other = Text("test.localeLanguage.greeting")
        #expect(one == other)
    }

    @Test("A text whose values spell words of their own buffer holds a source of its own, and reads its key again")
    func longWordsHoldTheirOwnSource() throws {
        // "Hello, " and the name: past the 15 bytes a string keeps in itself, so
        // each text's words are a buffer of their own and no lookup would make
        // two of them equal.
        let name = "Bartholomew Montgomery"
        let first = try #require(Text("test.localeLanguage.named \(name)").localization)
        let second = try #require(Text("test.localeLanguage.named \(name)").localization)
        #expect(first !== second)
        #expect(first == second)
        let german = Text("test.localeLanguage.named \(name)").environment(\.locale, Locale(identifier: "de"))
        #expect(drawn(german, width: 40).contains("Hallo, \(name)"), "\(drawn(german, width: 40))")
    }

    @Test("A text whose values spell words that fit in the string itself holds the kept source")
    func shortWordsHoldTheKeptSource() throws {
        let first = try #require(Text("test.localeLanguage.named \("Al")").localization)
        let second = try #require(Text("test.localeLanguage.named \("Al")").localization)
        #expect(first === second)
        let one = Text("test.localeLanguage.named \("Al")")
        let other = Text("test.localeLanguage.named \("Al")")
        #expect(one == other)
    }

    @Test("Setting the locale names the string language; the root's publication does not")
    func environmentKeys() {
        var environment = EnvironmentValues()
        #expect(environment.stringLanguage == nil)
        environment.publishUserLocale(Locale(identifier: "de_DE"))
        #expect(environment.stringLanguage == nil, "the root's strings are already the user's")
        environment.locale = Locale(identifier: "fr_CA")
        #expect(environment.stringLanguage == "fr")
    }
}
