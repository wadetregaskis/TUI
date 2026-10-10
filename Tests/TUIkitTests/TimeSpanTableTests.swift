//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimeSpanTableTests.swift
//
//  A span of a month or more spelt from the framework's own tables — what the
//  open-source Foundation, which cannot spell years and months, spells one with
//  — held to Apple's `Date.ComponentsFormatStyle` in all seven languages.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

@MainActor
@Suite("Spans spelt from the framework's tables")
struct TimeSpanTableTests {
    nonisolated private static let languages = ["en", "de", "fr", "it", "es", "zh", "ja"]

    /// Spans with years or months, as `TimeSpanField`s.
    private static let spans: [[TimeSpanField]] = [
        [TimeSpanField(unit: .year, value: 0)],
        [TimeSpanField(unit: .year, value: 1)],
        [TimeSpanField(unit: .year, value: 2)],
        [TimeSpanField(unit: .year, value: 21)],
        [TimeSpanField(unit: .month, value: 1)],
        [TimeSpanField(unit: .month, value: 11)],
        [TimeSpanField(unit: .year, value: 1), TimeSpanField(unit: .month, value: 3)],
        [TimeSpanField(unit: .year, value: 2), TimeSpanField(unit: .month, value: 1)],
        [TimeSpanField(unit: .month, value: 2), TimeSpanField(unit: .day, value: 5)],
        [TimeSpanField(unit: .month, value: 2), TimeSpanField(unit: .week, value: 1)],
        [
            TimeSpanField(unit: .year, value: 1), TimeSpanField(unit: .month, value: 3),
            TimeSpanField(unit: .day, value: 2),
        ],
    ]

    #if !canImport(FoundationEssentials)
        @Test(
            "The tables spell a span as Date.ComponentsFormatStyle does, in every language and width",
            arguments: languages, [TimeSpanWidth.wide, .abbreviated])
        func matchesApple(language: String, width: TimeSpanWidth) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let locale = Locale(identifier: language)
            for fields in Self.spans {
                // `unitList` takes Apple's path for years and months here.
                let apple = TimeSpan.unitList(fields, width: width, locale: locale, calendar: calendar)
                let tables = TimeSpan.tableUnitList(fields, width: width, locale: locale)
                #expect(tables == apple, "\(language) \(fields.map { "\($0.value) \($0.unit)" })")
            }
        }
    #endif

    @Test("Years and months are spelt in the locale's language, and joined as its units are")
    func spelt() {
        let span = [TimeSpanField(unit: .year, value: 1), TimeSpanField(unit: .month, value: 3)]
        #expect(TimeSpan.tableUnitList(span, width: .wide, locale: Locale(identifier: "de")) == "1 Jahr und 3 Monate")
        #expect(TimeSpan.tableUnitList(span, width: .abbreviated, locale: Locale(identifier: "en")) == "1 yr, 3 mths")
        #expect(TimeSpan.tableUnitList(span, width: .wide, locale: Locale(identifier: "zh")) == "1年3个月")
        #expect(
            TimeSpan.tableUnitList([TimeSpanField(unit: .year, value: 0)], width: .wide, locale: Locale(identifier: "fr"))
                == "0\u{00A0}an",
            "French counts zero as one")
    }

    @Test("A locale the framework has no words for takes English names")
    func otherLanguages() {
        #expect(TimeSpanLanguage(Locale(identifier: "pt_BR")).language == .english)
        #expect(TimeSpanLanguage(Locale(identifier: "zh-Hant")).language == .english, "the tables' Chinese is Simplified")
        #expect(TimeSpanLanguage(Locale(identifier: "zh_TW")).language == .english)
        #expect(TimeSpanLanguage(Locale(identifier: "zh-Hans")).language == .simplifiedChinese)
        #expect(TimeSpanLanguage(Locale(identifier: "de_AT")).language == .german)
    }

    @Test("Each language's units are separated as Duration.UnitsFormatStyle separates them")
    func separators() {
        let german = TimeSpan.unitSeparators(width: .wide, locale: Locale(identifier: "de"))
        #expect(german.pair == " und " && german.start == ", " && german.end == " und ")
        let english = TimeSpan.unitSeparators(width: .abbreviated, locale: Locale(identifier: "en"))
        #expect(english.pair == ", " && english.end == ", ")
        #expect(TimeSpan.unitSeparators(width: .wide, locale: Locale(identifier: "zh")).pair.isEmpty)
    }
}
