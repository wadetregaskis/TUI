//  🖥️ TUI — A Terminal UI framework for Swift
//  InterpolatedNumberTests.swift
//
//  A number interpolated into a key with no specifier is written in the
//  locale, as SwiftUI writes it, but a floating-point one is not padded to
//  six digits, as SwiftUI's is (owner ruling B-TEXTFMT-1, 2026-10-24;
//  Deliberate deviations T11). One with a specifier, `\(x, specifier:
//  "%.2f")`, is written by exactly that conversion, in the same locale.
//  Every locale here is explicit: the process's own, and the app's, are
//  whatever the machine running the tests says.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@Suite("A number interpolated into a key is written in the locale")
struct InterpolatedNumberTests {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")
    private static let french = Locale(identifier: "fr_FR")

    /// French groups with a narrow no-break space, U+202F.
    private static let narrowSpace = "\u{202F}"

    // MARK: - How a number is written

    @Test("An integer is grouped as the locale groups it")
    func integers() {
        let number = InterpolatedNumber(1_234_567)
        #expect(number.formatted(in: Self.english) == "1,234,567")
        #expect(number.formatted(in: Self.german) == "1.234.567")
        #expect(number.formatted(in: Self.french) == "1\(Self.narrowSpace)234\(Self.narrowSpace)567")
        #expect(InterpolatedNumber(Int8(-5)).formatted(in: Self.english) == "-5")
        #expect(InterpolatedNumber(UInt64.max).formatted(in: Self.english) == "18,446,744,073,709,551,615")
        #expect(InterpolatedNumber(Int64.min).formatted(in: Self.english) == "-9,223,372,036,854,775,808")
    }

    @Test("A floating-point number has the locale's separators and no padding")
    func floatingPoint() {
        #expect(InterpolatedNumber(3.5).formatted(in: Self.english) == "3.5")
        #expect(InterpolatedNumber(3.5).formatted(in: Self.german) == "3,5")
        #expect(InterpolatedNumber(3.5).formatted(in: Self.french) == "3,5")
        #expect(InterpolatedNumber(1_234_567.891).formatted(in: Self.german) == "1.234.567,891")
        #expect(InterpolatedNumber(2.0).formatted(in: Self.english) == "2", "a whole number has no fraction")
    }

    @Test("At most six fraction digits, %lf's precision, so 0.1 + 0.2 is not seventeen digits")
    func precision() {
        #expect(InterpolatedNumber(0.1 + 0.2).formatted(in: Self.english) == "0.3")
        #expect(InterpolatedNumber(Double.pi).formatted(in: Self.english) == "3.141593")
        #expect(InterpolatedNumber(Float(0.1)).formatted(in: Self.english) == "0.1", "a Float's widening is not seen")
        #expect(InterpolatedNumber(CGFloat(2.25)).formatted(in: Self.english) == "2.25")
    }

    @Test("The values printf writes oddly are written as .number writes them")
    func specialValues() {
        #expect(InterpolatedNumber(-0.0).formatted(in: Self.english) == "-0")
        #expect(InterpolatedNumber(Double.nan).formatted(in: Self.english) == "NaN")
        #expect(InterpolatedNumber(Double.infinity).formatted(in: Self.english) == "∞")
        let nan = InterpolatedNumber(Double.nan)
        let sameNaN = InterpolatedNumber(Double.nan)
        #expect(nan == sameNaN, "a memo's key equals itself")
        #expect(InterpolatedNumber(-0.0) != InterpolatedNumber(0.0))
    }

    @Test("Each standard number type is kept as the number it is", arguments: [
        (InterpolatedNumber(Int(-7)), InterpolatedNumber.signed(-7)),
        (InterpolatedNumber(Int8(-7)), .signed(-7)), (InterpolatedNumber(Int16(-7)), .signed(-7)),
        (InterpolatedNumber(Int32(-7)), .signed(-7)), (InterpolatedNumber(Int64(-7)), .signed(-7)),
        (InterpolatedNumber(UInt(7)), .unsigned(7)), (InterpolatedNumber(UInt8(7)), .unsigned(7)),
        (InterpolatedNumber(UInt16(7)), .unsigned(7)), (InterpolatedNumber(UInt32(7)), .unsigned(7)),
        (InterpolatedNumber(UInt64(7)), .unsigned(7)), (InterpolatedNumber(Float(0.5)), InterpolatedNumber(0.5)),
        (InterpolatedNumber(CGFloat(0.5)), InterpolatedNumber(0.5)),
    ])
    func kinds(_ made: InterpolatedNumber, _ expected: InterpolatedNumber) {
        #expect(made == expected)
    }

    // MARK: - The key

    private let configDir = NSTemporaryDirectory() + "tuikit-numfmt-\(UUID().uuidString)"

    /// A service of the test's own in `language`, its region the one `lang`
    /// names, so its locale is that whatever the machine's: the region, not
    /// the language, decides how a number is grouped (`de_US` writes
    /// `1,234,567`).
    private func service(_ language: LocalizationService.Language, lang: String) -> LocalizationService {
        let service = LocalizationService(configDirectoryPath: configDir, environment: ["LANG": lang])
        service.pinLanguageForTesting(language)
        return service
    }

    @Test("The key is SwiftUI's, so a translation keyed %lld or %lf still matches")
    func keyUnchanged() {
        let key: LocalizedStringKey = "Count: \(1_234_567) of \(3.5)"
        #expect(key.key == "Count: %@ of %@")
        #expect(key.swiftUIKey == "Count: %lld of %lf")
        let translations = [
            "en": ["Count: %lld of %lf": "Total %lld, ratio %lf"], "de": ["Count: %lld of %lf": "Summe %lld, Anteil %lf"],
        ]
        let english = service(.english, lang: "en_US.UTF-8")
        english.register(translations: translations)
        #expect(key.resolved(with: english) == "Total 1,234,567, ratio 3.5")
        let german = service(.german, lang: "de_DE.UTF-8")
        german.register(translations: translations)
        #expect(key.resolved(with: german) == "Summe 1.234.567, Anteil 3,5", "the service's locale writes them")
    }

    @Test("No number is padded to six digits, in any locale")
    func neverPadded() {
        let key: LocalizedStringKey = "\(3.5) \(Float(3.25)) \(CGFloat(1))"
        for locale in [Self.english, Self.german, Self.french] {
            let words = key.formattingNumbers(in: locale).arguments.joined(separator: " ")
            #expect(!words.contains("00"), "\(locale.identifier): \(words)")
        }
    }

    @Test("A number unchanged from frame to frame is written once, and again only when the locale moves")
    func keptPerLocale() {
        let service = service(.english, lang: "de_DE.UTF-8")
        let number = InterpolatedNumber(1_234_567)
        for _ in 0..<100 { #expect(service.formatted(number) == "1.234.567") }
        #expect(service.numbersFormatted == 1, "a body run every frame looks the number up")
        _ = service.formatted(InterpolatedNumber(42))
        #expect(service.numbersFormatted == 2, "another number is written")
        service.pinLanguageForTesting(.german)
        #expect(service.formatted(number) == number.formatted(in: service.currentLocale))
        #expect(service.numbersFormatted == 3, "the new locale writes it afresh")
        _ = service.formatted(number)
        #expect(service.numbersFormatted == 3)
    }

    @Test("A key's number is the shared service's, written in its locale")
    func builtThroughTheSharedService() {
        let key: LocalizedStringKey = "v \(1_234_567)"
        let shared = LocalizationService.shared
        #expect(key.arguments == [InterpolatedNumber(1_234_567).formatted(in: shared.currentLocale)])
        #expect(key.numberArguments == [0: .signed(1_234_567)])
    }

    @Test("A number keeps its place among the other values")
    func place() {
        let key: LocalizedStringKey = "\("a") \(1_000) \("b") \(2.5)"
        #expect(key.numberArguments == [1: .signed(1_000), 3: InterpolatedNumber(2.5)])
        #expect(key.formattingNumbers(in: Self.german).arguments == ["a", "1.000", "b", "2,5"])
    }

    // MARK: - A specifier

    @Test("A specifier's conversion is written in the locale: %.2f and %d in en, de and fr", arguments: [
        (Locale(identifier: "en_US"), "234.50", "234.57", "42"),
        (Locale(identifier: "de_DE"), "234,50", "234,57", "42"),
        (Locale(identifier: "fr_FR"), "234,50", "234,57", "42"),
    ])
    func specifiers(_ locale: Locale, _ padded: String, _ rounded: String, _ integer: String) {
        #expect(InterpolatedNumber(234.5, specifier: "%.2f").formatted(in: locale) == padded, "padding is the conversion's own")
        #expect(InterpolatedNumber(234.567, specifier: "%.2f").formatted(in: locale) == rounded)
        #expect(InterpolatedNumber(42, specifier: "%d").formatted(in: locale) == integer)
        #expect(InterpolatedNumber(Int32(42), specifier: "%d").formatted(in: locale) == integer)
    }

    @Test("Each width is given the conversion at the width C promotes it to")
    func specifiedWidths() {
        let english = Self.english
        #expect(InterpolatedNumber(Int32(-5), specifier: "%d").formatted(in: english) == "-5")
        #expect(InterpolatedNumber(Int8(-5), specifier: "%d").formatted(in: english) == "-5")
        // Foundation groups a conversion's integer in the locale on Apple's
        // platforms and not everywhere, so the digits are what is compared.
        let digits = { (number: InterpolatedNumber) in number.formatted(in: english).filter(\.isNumber) }
        #expect(digits(InterpolatedNumber(Int.min, specifier: "%lld")) == "9223372036854775808", "all 64 bits")
        #expect(digits(InterpolatedNumber(UInt.max, specifier: "%llu")) == "18446744073709551615", "all 64 bits")
        #expect(InterpolatedNumber(UInt8(200), specifier: "%u").formatted(in: english) == "200")
        #expect(InterpolatedNumber(255, specifier: "%llx").formatted(in: english) == "ff")
        #expect(InterpolatedNumber(Float(2.5), specifier: "%.1f").formatted(in: english) == "2.5")
        #expect(InterpolatedNumber(CGFloat(2.25), specifier: "%.3f").formatted(in: english) == "2.250")
        #expect(InterpolatedNumber(Double.pi, specifier: "%.10f").formatted(in: Self.german) == "3,1415926536")
    }

    @Test("The same value under two specifiers is two numbers")
    func specifierIsPartOfTheNumber() {
        #expect(InterpolatedNumber(2.5, specifier: "%.1f") != InterpolatedNumber(2.5, specifier: "%.2f"))
        #expect(InterpolatedNumber(2.5, specifier: "%.1f") != InterpolatedNumber(2.5))
        let again = InterpolatedNumber(2.5, specifier: "%.1f")
        #expect(InterpolatedNumber(2.5, specifier: "%.1f") == again)
    }

    @Test("A specifier's key is SwiftUI's, so a translation keyed with it still matches, in each locale")
    func specifierKey() {
        let key: LocalizedStringKey = "Price \(234.5, specifier: "%.2f") for \(3, specifier: "%d")"
        #expect(key.key == "Price %@ for %@")
        #expect(key.swiftUIKey == "Price %.2f for %d")
        let translations = [
            "en": ["Price %.2f for %d": "Cost %.2f x%d"], "de": ["Price %.2f for %d": "Preis %.2f für %d"],
            "fr": ["Price %.2f for %d": "Prix %.2f pour %d"],
        ]
        for (language, lang, expected) in [
            (LocalizationService.Language.english, "en_US.UTF-8", "Cost 234.50 x3"),
            (.german, "de_DE.UTF-8", "Preis 234,50 für 3"), (.french, "fr_FR.UTF-8", "Prix 234,50 pour 3"),
        ] {
            let service = service(language, lang: lang)
            service.register(translations: translations)
            #expect(key.resolved(with: service) == expected)
        }
    }

    @Test("A specifier's number keeps its place and is written afresh in another locale")
    func specifierPlace() {
        let key: LocalizedStringKey = "\("a") \(2.5, specifier: "%.2f") \(1_000) \(7, specifier: "%03d")"
        #expect(key.numberArguments.keys.sorted() == [1, 2, 3])
        #expect(key.formattingNumbers(in: Self.german).arguments == ["a", "2,50", "1.000", "007"])
        #expect(key.formattingNumbers(in: Self.english).arguments == ["a", "2.50", "1,000", "007"])
    }

    @Test("A specifier's number is written once while unchanged, and again when the locale moves")
    func specifierKeptPerLocale() {
        let service = service(.english, lang: "de_DE.UTF-8")
        let number = InterpolatedNumber(234.5, specifier: "%.2f")
        for _ in 0..<100 { #expect(service.formatted(number) == "234,50") }
        #expect(service.numbersFormatted == 1)
        service.pinLanguageForTesting(.french)
        #expect(service.formatted(number) == number.formatted(in: service.currentLocale))
        #expect(service.numbersFormatted == 2)
    }

    @Test("A key's specifier is written through the shared service, in its locale")
    func specifierBuiltThroughTheSharedService() {
        let key: LocalizedStringKey = "v \(234.5, specifier: "%.2f")"
        let locale = LocalizationService.shared.currentLocale
        #expect(key.arguments == [InterpolatedNumber(234.5, specifier: "%.2f").formatted(in: locale)])
        #expect(key.numberArguments == [0: InterpolatedNumber(234.5, specifier: "%.2f")])
    }
}

// MARK: - Drawn

@MainActor
@Suite("A Text's interpolated number follows \\.locale", .rendersEnglishUI)
struct InterpolatedNumberTextTests {
    private func drawn(_ view: some View, width: Int = 40) -> String {
        let context = makeBareRenderContext(width: width, height: 3)
        return renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
    }

    private func text() -> Text {
        Text("n \(1_234_567) r \(3.5)")
    }

    @Test("Under en_US, de_DE and fr_FR a Text writes the locale's number", arguments: [
        ("en_US", "n 1,234,567 r 3.5"), ("de_DE", "n 1.234.567 r 3,5"),
        ("fr_FR", "n 1\u{202F}234\u{202F}567 r 3,5"),
    ])
    func drawnInTheLocale(_ identifier: String, _ expected: String) {
        let lines = drawn(text().environment(\.locale, Locale(identifier: identifier)))
        #expect(lines.contains(expected), "\(lines)")
        #expect(!lines.contains("500000"))
    }

    @Test("A locale of the app's language but another region writes its numbers again")
    func sameLanguageOtherRegion() {
        let lines = drawn(text().environment(\.locale, Locale(identifier: "en_IN")))
        #expect(lines.contains("n 12,34,567 r 3.5"), "\(lines)")
    }

    @Test("The same Text under another locale is written again")
    func localeChange() {
        let view = VStack {
            text().environment(\.locale, Locale(identifier: "de_DE"))
            text().environment(\.locale, Locale(identifier: "en_US"))
            text().environment(\.locale, Locale(identifier: "de_CH"))
        }
        let lines = drawn(view).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines.first?.contains("1.234.567") == true, "\(lines)")
        #expect(lines.dropFirst().first?.contains("1,234,567") == true, "\(lines)")
        // Foundation's: ’ before macOS 26 and on Linux, ' from it.
        let swiss = IntegerFormatStyle<Int>(locale: Locale(identifier: "de_CH")).format(1_234_567)
        #expect(lines.last?.contains(swiss) == true, "\(lines)")
    }

    @Test("A styled Text keeps its number in the locale too")
    func styled() {
        let lines = drawn(Text("**n** \(1_234)").environment(\.locale, Locale(identifier: "de_DE")))
        #expect(lines.contains("n 1.234"), "\(lines)")
    }

    @Test("A live Text writes its number in the locale while its clock reads on")
    func live() {
        let view = Text("n \(1_234) \(Date(), style: .relative)").environment(\.locale, Locale(identifier: "de_DE"))
        #expect(drawn(view).contains("n 1.234"), "\(drawn(view))")
    }

    @Test("A specifier's number follows \\.locale too: %.2f and %d under en, de and fr", arguments: [
        ("en_US", "p 234.50 n 007"), ("de_DE", "p 234,50 n 007"), ("fr_FR", "p 234,50 n 007"),
    ])
    func specifierDrawnInTheLocale(_ identifier: String, _ expected: String) {
        let view = Text("p \(234.5, specifier: "%.2f") n \(7, specifier: "%03d")")
            .environment(\.locale, Locale(identifier: identifier))
        let lines = drawn(view)
        #expect(lines.contains(expected), "\(lines)")
    }

    @Test("A change of \\.locale writes a specifier's number again, German, English, French")
    func specifierLocaleChange() {
        let view = VStack {
            Text("\(234.5, specifier: "%.2f")").environment(\.locale, Locale(identifier: "de_DE"))
            Text("\(234.5, specifier: "%.2f")").environment(\.locale, Locale(identifier: "en_US"))
            Text("\(234.5, specifier: "%.2f")").environment(\.locale, Locale(identifier: "fr_FR"))
        }
        let lines = drawn(view).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines == ["234,50", "234.50", "234,50"], "\(lines)")
    }

    @Test("A translation keyed with the specifier is found and its number follows \\.locale")
    func specifierTranslated() {
        LocalizationService.shared.register(translations: ["en": ["test.spec price %.2f": "test.spec cost %.2f"]])
        let view = Text("test.spec price \(234.5, specifier: "%.2f")").environment(\.locale, Locale(identifier: "de_DE"))
        #expect(drawn(view).contains("test.spec cost 234,50"), "\(drawn(view))")
    }
}
