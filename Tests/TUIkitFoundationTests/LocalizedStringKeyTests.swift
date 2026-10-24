//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKeyTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

/// `LocalizedStringKey` — SwiftUI's "a string literal is a lookup key" rule.
///
/// Two things are load-bearing and neither is obvious. First, WHICH overload a
/// call binds to: a literal must be a key and a computed `String` must not, or
/// a file path would be looked up as one. Second, the fallback: a key with no
/// translation must come back as itself, because that is what makes adopting
/// this change nothing for an app that ships no translations.
@MainActor
@Suite("LocalizedStringKey")
struct LocalizedStringKeyTests {

    /// A service with its own config directory, so nothing here reads or
    /// writes the developer's real language preference.
    private func isolatedService() -> LocalizationService {
        LocalizationService(
            configDirectoryPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("tuikit-lsk-tests").path)
    }

    // MARK: - Which overload binds

    @Test("A literal is a key; a String variable is content")
    func overloadResolution() {
        // The whole design rests on this, and it is plain overload resolution
        // rather than anything magic: `LocalizedStringKey` is concrete, the
        // String initializer is generic, and Swift prefers concrete for a
        // literal.
        let key: LocalizedStringKey = "some.key"
        #expect(key.key == "some.key")
        #expect(key.arguments.isEmpty)

        // A computed String must never be treated as a key — it could be a
        // file path, a user's name, anything.
        let computed = "some.key"
        #expect(Text(computed).content == "some.key")
        #expect(Text(verbatim: "some.key").content == "some.key")
    }

    @Test("A Substring binds too")
    func substringBinds() {
        // The generic `StringProtocol` overload is what SwiftUI has, and it
        // buys this: slicing no longer needs an explicit String(...).
        let sentence = "hello world"
        let first = sentence.prefix(5)
        #expect(Text(first).content == "hello")
    }

    // MARK: - Lookup and fallback

    @Test("A key with no translation comes back as itself")
    func fallsBackToTheLiteral() {
        // The property that makes this behaviour-preserving: an app that
        // registers nothing sees exactly the literals it wrote.
        let service = isolatedService()
        let key: LocalizedStringKey = "Not a registered key at all"
        #expect(key.resolved(with: service) == "Not a registered key at all")
    }

    @Test("A registered key resolves to its translation")
    func resolvesARegisteredKey() {
        let service = isolatedService()
        service.register(translations: [
            "en": ["test.lsk.greeting": "Good morning"]
        ])
        let key: LocalizedStringKey = "test.lsk.greeting"
        #expect(key.resolved(with: service) == "Good morning")
    }

    @Test("Text runs a literal through the lookup")
    func textLooksUp() {
        // Registration is in-memory and the key is namespaced to this test, so
        // it cannot collide with anything the app or another suite asks for.
        LocalizationService.shared.register(translations: [
            "en": ["test.lsk.textpath": "resolved through the service"]
        ])
        #expect(Text("test.lsk.textpath").content == "resolved through the service")
        // …and the opt-out still opts out.
        #expect(Text(verbatim: "test.lsk.textpath").content == "test.lsk.textpath")
    }

    @Test("A runtime key looks up once it is asked to be one")
    func explicitKeyFromAVariableLooksUp() {
        // The answer to "my key is in a variable, how do I localise it?" — and
        // the reason the String overload's silence is a design and not a gap.
        // Wrapping is the request; without it a `String` is content, because
        // nothing else can tell a key from a user's name. The Theme page demos
        // all four spellings side by side.
        LocalizationService.shared.register(translations: [
            "en": ["test.lsk.runtimekey": "resolved from a variable"]
        ])
        let computed = "test.lsk" + ".runtimekey"
        #expect(Text(computed).content == "test.lsk.runtimekey")
        #expect(Text(LocalizedStringKey(computed)).content == "resolved from a variable")
    }

    // MARK: - Interpolation

    @Test("Interpolation builds one key for every value")
    func interpolationBuildsAKey() {
        // The point of `%@`: one table entry serves every value, so a
        // translator writes the sentence once.
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.key == "Moved %@ rows to %@")
        #expect(key.arguments == ["3", "Backlog"])
    }

    @Test("An untranslated interpolation reads as it was written")
    func interpolationFallback() {
        let service = isolatedService()
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.resolved(with: service) == "Moved 3 rows to Backlog")
    }

    @Test("Interpolating a system image contributes its glyph, and a picture nothing")
    func interpolatingAnImage() {
        // The deviations sweep's likely bug 24 (semantic audit 58): SwiftUI
        // draws an interpolated `Image` inline; the catch-all drew the struct.
        let service = isolatedService()
        let key: LocalizedStringKey = "\(Image(systemName: "star")) Favourites"
        #expect(key.key == "%@ Favourites")
        #if canImport(AppKit)
            #expect(key.resolved(with: service) == (SFSymbol.glyph(named: "star") ?? "") + " Favourites")
            #expect(SFSymbol.glyph(named: "star") != nil, "sanity: the symbol table has a star")
        #else
            #expect(key.resolved(with: service) == " Favourites")
            #expect(SFSymbol.glyph(named: "star") == nil)
        #endif
    }

    @Test("Text(_:) of an image is its glyph, as interpolating the image gives, and nothing for an unknown symbol")
    func textOfAnImage() throws {
        // SwiftUI's `Text(_ image: Image)`, the audit's verifier finding.
        #if canImport(AppKit)
            let star = try #require(SFSymbol.glyph(named: "star.fill"))
            #expect(Text(Image(systemName: "star.fill")).content == star)
            #expect(Text(Image(systemName: "no.such.symbol")).content.isEmpty)
            let key: LocalizedStringKey = "\(Text(Image(systemName: "star.fill"))) Favourites"
            #expect(key.resolved(with: isolatedService()) == star + " Favourites")
        #else
            #expect(Text(Image(systemName: "star.fill")).content.isEmpty)
            #expect(Text(Image(systemName: "no.such.symbol")).content.isEmpty)
        #endif
    }

    @Test("Interpolating a Text contributes its own content, not its debug description")
    func interpolatingATextContributesItsContent() {
        // SwiftUI lets a `Text` interpolate another `Text` (and an `Image`)
        // straight into a `LocalizedStringKey`. Without a dedicated overload
        // here, the unconstrained `appendInterpolation(_ value: some Any)`
        // catch-all takes it instead and `String(describing:)`s the whole
        // struct — style and all — rather than reading its text.
        let service = isolatedService()
        let nameText = Text("Alice")
        let key: LocalizedStringKey = "Hello, \(nameText)"
        let resolved = key.resolved(with: service)
        #expect(resolved.contains("Hello, Alice"))
        #expect(!resolved.contains("Text("))
    }

    @Test("A translation can reorder the values")
    func positionalArguments() {
        // Word order differs between languages; without positions a
        // translation would be stuck with the English order.
        let service = isolatedService()
        service.register(translations: [
            "en": ["test.lsk.order": "%2$@ gained %1$@ rows"]
        ])
        let key = LocalizedStringKey(key: "test.lsk.order", arguments: ["3", "Backlog"])
        #expect(key.resolved(with: service) == "Backlog gained 3 rows")
    }

    @Test("A value can be formatted where it is interpolated")
    func formatStyleInterpolation() {
        let service = isolatedService()
        let key: LocalizedStringKey = "Done: \(0.5, format: .percent)"
        #expect(key.key == "Done: %@")
        #expect(key.resolved(with: service) == "Done: \(0.5.formatted(.percent))")
    }

    // MARK: - Percent signs that are not placeholders

    @Test("A literal with no values is never scanned")
    func percentInAPlainLiteral() {
        // The common case, and the one that would be most annoying to get
        // wrong: `Text("100% done")` says 100% done.
        let service = isolatedService()
        let key: LocalizedStringKey = "100% done"
        #expect(key.arguments.isEmpty)
        #expect(key.resolved(with: service) == "100% done")
    }

    @Test("A stray percent survives alongside a real placeholder")
    func percentBesideAPlaceholder() {
        // Here scanning IS running, so the `%` has to reach the output rather
        // than swallowing the character after it. The KEY carries it escaped,
        // because the key is printf-shaped and `%%` is how that alphabet
        // spells one percent — which is also what a translator writes in a
        // strings file, and what `substituting` has always accepted.
        let service = isolatedService()
        let key: LocalizedStringKey = "\(50)% of the way"
        #expect(key.key == "%@%% of the way")
        #expect(key.resolved(with: service) == "50% of the way")
    }

    @Test("A percent immediately before an interpolation keeps both")
    func percentImmediatelyBeforeAPlaceholder() {
        // The case the escaping exists for. Unescaped, the literal `%` and the
        // following `%@` fused into `%%` + a stray `@`, so the second argument
        // was dropped and an `@` appeared where it should have been.
        let service = isolatedService()
        let key: LocalizedStringKey = "Save \(5)%\("now")"
        #expect(key.key == "Save %@%%%@")
        #expect(key.resolved(with: service) == "Save 5%now")

        // And a literal percent with no interpolation at all is untouched,
        // since nothing scans a key that has no arguments.
        let bare: LocalizedStringKey = "100% done"
        #expect(bare.resolved(with: service) == "100% done")
    }

    @Test("Percent escapes and C conversions a translator might write")
    func substitutionForms() {
        // These go through `substituting` directly: the strings come from
        // translators, not from the interpolation builder, so they can contain
        // anything a strings file can.
        #expect(LocalizedStringKey.substituting(["x"], into: "100%% and %@") == "100% and x")
        #expect(LocalizedStringKey.substituting(["7"], into: "%d items") == "7 items")
        #expect(LocalizedStringKey.substituting(["7"], into: "%lld items") == "7 items")
    }

    @Test("A width after a position pads like a width before one")
    func positionalWidth() {
        // printf allows `%2$3d`: position first, then the flags and width. A
        // scan that stopped at the `$` took the `3` for the conversion and
        // emitted the `%` verbatim, dropping the argument.
        #expect(LocalizedStringKey.substituting(["10", "2"], into: "Zeile %2$3d von %1$d") == "Zeile   2 von 10")
        #expect(LocalizedStringKey.substituting(["ab"], into: "[%1$-4@]") == "[ab  ]")
    }

    // MARK: - Value semantics

    @Test("Keys compare by key and arguments")
    func equality() {
        // `Text` is `Equatable` and the render memo leans on it, so a key that
        // compared only by its template would serve a stale buffer when only
        // the interpolated value changed.
        let one: LocalizedStringKey = "Rows: \(1)"
        let two: LocalizedStringKey = "Rows: \(2)"
        #expect(one != two)
        #expect(one == LocalizedStringKey(key: "Rows: %@", swiftUIKey: "Rows: %lld", arguments: ["1"]))
        // The same template and argument from a String is another lookup: only
        // the Int's finds a catalog keyed `Rows: %lld`, as SwiftUI keys it.
        let fromString: LocalizedStringKey = "Rows: \("1")"
        #expect(fromString.key == one.key && fromString.arguments == one.arguments)
        #expect(one != fromString)
    }

    @Test("A width counts cells, not graphemes")
    func widthIsCells() {
        // Two CJK graphemes occupy four cells: no padding at `%4@`, two at `%6@`.
        #expect(LocalizedStringKey.substituting(["日本"], into: "[%4@]") == "[日本]")
        #expect(LocalizedStringKey.substituting(["日本"], into: "[%6@]") == "[  日本]")
        #expect(LocalizedStringKey.substituting(["a", "b"], into: "%@%@") == "ab")
        // A position may repeat; the implicit cursor is not advanced by one.
        #expect(LocalizedStringKey.substituting(["a", "b"], into: "%1$@%1$@") == "aa")
        // Missing arguments leave the placeholder empty rather than trapping.
        #expect(LocalizedStringKey.substituting(["a"], into: "%@%@") == "a")
        // A trailing lone percent is emitted, not dropped.
        #expect(LocalizedStringKey.substituting(["a"], into: "%@ 100%") == "a 100%")
        // A WIDTH pads the value and, crucially, still consumes its argument:
        // the old scan rewound onto the digits, emitted %3d verbatim, and
        // delivered the first argument to the SECOND placeholder.
        #expect(LocalizedStringKey.substituting(["2", "10"], into: "Zeile %3d von %d") == "Zeile   2 von 10")
        #expect(LocalizedStringKey.substituting(["ab"], into: "[%-4d]") == "[ab  ]")
        #expect(LocalizedStringKey.substituting(["3.14"], into: "%.2f rad") == "3.14 rad")
    }

    /// SplitMix64, so the sampled templates are the same on every run and platform.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    @Test("The bare-placeholder substitution agrees with the walk wherever it answers")
    func barePlaceholderFastPathAgreesWithWalk() {
        // `substituting` answers an all-ASCII template of bare `%@`s from its
        // bytes and leaves every other template to the walk. Where it answers,
        // it must say what the walk says — and it must decline the forms it
        // cannot read, or a `%%` or `%2$@` would come out wrong.
        #expect(LocalizedStringKey.substitutingBarePlaceholders(["x", "y"], into: "a %@ b %@!") == "a x b y!")
        #expect(LocalizedStringKey.substitutingBarePlaceholders(["x"], into: "%@ and %@") == "x and ")
        #expect(LocalizedStringKey.substitutingBarePlaceholders([], into: "no placeholders") == "no placeholders")
        for declined in ["100%% and %@", "%2$@ %1$@", "%d items", "%@ 100%", "%3@", "é %@", "%@ 日本"] {
            #expect(
                LocalizedStringKey.substitutingBarePlaceholders(["x", "y"], into: declined) == nil,
                "\(declined) is the walk's to read")
        }

        // Then a few thousand templates built from the pieces either side of
        // the line: bare and positional placeholders, escapes, widths, a
        // trailing percent, CR LF (the one ASCII pair that is ONE Character),
        // a combining mark, wide and non-ASCII text.
        let pieces = [
            "%@", "%@", "%@", "a", "b", " ", "@", "%", "%%", "%1$@", "%2$@", "%-3@", "%3@", "%d",
            "\r\n", "\r", "\n", "e\u{301}", "\u{301}", "日", "é", "🇦🇺", ".",
        ]
        let values = ["", "x", "yy", "日本", "%@", "%%", "a b"]
        var generator = SeededGenerator(state: 0x5EED_F00D)
        var answered = 0
        for _ in 0..<4_000 {
            var template = ""
            for _ in 0..<Int.random(in: 0...8, using: &generator) {
                template += pieces.randomElement(using: &generator)!
            }
            let arguments = (0..<Int.random(in: 0...3, using: &generator)).map { _ in
                values.randomElement(using: &generator)!
            }
            let walked = LocalizedStringKey.substitutingByWalk(arguments, into: template)
            if let fast = LocalizedStringKey.substitutingBarePlaceholders(arguments, into: template) {
                answered += 1
                #expect(Array(fast.utf8) == Array(walked.utf8), "\(template.debugDescription) \(arguments)")
            }
            #expect(
                Array(LocalizedStringKey.substituting(arguments, into: template).utf8) == Array(walked.utf8),
                "\(template.debugDescription) \(arguments)")
        }
        // Not vacuous: a good share of the samples took the fast path.
        #expect(answered > 400, "only \(answered) templates took the fast path")
    }

    @Test("A String, an Int and anything else is what String(describing:) makes of it, whatever its static type")
    func describingFastPathAgrees() {
        // A String and an Int take their own overloads, the Int without
        // `String(describing:)`'s conformance probes, and must agree with it;
        // so must the look-alikes that reach the deprecated catch-all: an
        // Optional (described as `Optional(…)`) and a value boxed in `Any`.
        let name = "Ada"
        let empty = ""
        let count = 42
        let negative = Int.min
        let optional: String? = "Ada"
        let boxed: Any = "Ada"
        let boxedNumber: Any = 7
        // Built call by call rather than as a literal, so the Optional reaches
        // the catch-all as `String?` itself (`as Any` would box it), and the
        // catch-all is reached through `appendThroughCatchAll`, which draws
        // no deprecation warning.
        var interpolation = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: 7)
        interpolation.appendInterpolation(name)
        interpolation.appendInterpolation(empty)
        interpolation.appendInterpolation(count)
        interpolation.appendInterpolation(negative)
        appendThroughCatchAll(optional, to: &interpolation)
        appendThroughCatchAll(boxed, to: &interpolation)
        appendThroughCatchAll(boxedNumber, to: &interpolation)
        let key = LocalizedStringKey(stringInterpolation: interpolation)
        #expect(key.key == "%@%@%@%@%@%@%@")
        // SwiftUI's key: `%lld` for each Int, and `%@` for a number in `Any`,
        // which SwiftUI's catch-all takes as it takes anything.
        #expect(key.swiftUIKey == "%@%@%lld%lld%@%@%@")
        #expect(
            key.arguments == [
                String(describing: name), String(describing: empty), String(describing: count),
                String(describing: negative), String(describing: optional),
                String(describing: boxed), String(describing: boxedNumber),
            ])
        #expect(key.arguments[0] == "Ada")
        #expect(key.arguments[3] == "-9223372036854775808")
        #expect(key.arguments[4] == "Optional(\"Ada\")")
    }

    @Test("SwiftUI's typed overloads take what they name: a substring, a number, a Foundation value")
    func typedOverloads() {
        let word = "xyz".dropFirst()
        let url = URL(string: "https://example.com/a")!
        let percent = NumberFormatter()
        percent.numberStyle = .percent
        percent.locale = Locale(identifier: "en_US")
        let key: LocalizedStringKey =
            "\(word) \(2.5) \(Float(0.25)) \(UInt8(7)) \(url) \(NSNumber(value: 0.5), formatter: percent)"
        #expect(key.arguments == ["yz", "2.5", "0.25", "7", "https://example.com/a", "50%"])
        #expect(key.swiftUIKey == "%@ %lf %f %u %@ %@")
    }

    @Test("An interpolated AttributedString keeps its looks for the Text, its characters for everything else")
    func attributedStringInterpolation() {
        var underlined = AttributedString("Ada")
        underlined.underlineStyle = Text.LineStyle(pattern: .dash)
        let key: LocalizedStringKey = "Hello, \(underlined) and \(AttributedString("Bo"))"
        #expect(key.arguments == ["Ada", "Bo"])
        #expect(key.styledArguments[0]?.runs.first?.style.underline != nil)
        // A plain one says nothing about its looks, so it is words only.
        #expect(key.styledArguments[1] == nil)
        #expect(key.swiftUIKey == nil)
    }

    @Test("A time data source through a format style is a live argument")
    func timeDataSourceInterpolation() {
        guard #available(macOS 15, *) else { return }
        let start = Date(timeIntervalSinceNow: -125)
        let key: LocalizedStringKey = "Started \(.currentDate, format: .offset(to: start))"
        #expect(key.key == "Started %@")
        #expect(key.liveArguments[0] != nil)
        #expect(!key.arguments[0].isEmpty)
    }

    @Test("A specifier formats the value, as SwiftUI's interpolation does")
    func specifierInterpolation() {
        let price = 3.14159
        let count: Int32 = 255
        let key: LocalizedStringKey = "Total \(price, specifier: "%.2f") in \(count, specifier: "%x") parts"
        #expect(key.arguments == ["3.14", "ff"])
        #expect(key.key == "Total %@ in %@ parts")
        #expect(key.resolved(with: isolatedService()) == "Total 3.14 in ff parts")
    }
}

// MARK: - The deprecated catch-all, reached without its warning

/// Declares the catch-all's signature as a requirement, so a test can call it
/// through the conformance: a call through a protocol requirement draws no
/// deprecation warning, where a direct call to the deprecated witness does.
private protocol CatchAllInterpolating {
    mutating func appendInterpolation<T>(_ object: T)
}

extension LocalizedStringKey.StringInterpolation: CatchAllInterpolating {}

/// Interpolates `value` through the catch-all, whatever typed overload its
/// static type would otherwise pick.
private func appendThroughCatchAll(_ value: some Any, to interpolation: inout some CatchAllInterpolating) {
    interpolation.appendInterpolation(value)
}
