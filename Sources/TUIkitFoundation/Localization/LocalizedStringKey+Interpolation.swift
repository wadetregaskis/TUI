//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKey+Interpolation.swift
//
//  The typed interpolations of a `LocalizedStringKey`, SwiftUI's set: a string,
//  a number, an interpolated `Text` or `Image`, a number through a printf
//  specifier, a value through a format style or a `Formatter`, an attributed
//  string. The clock-reading ones are in `LocalizedStringKey+Live.swift`; the
//  deprecated catch-all for anything else is in `LocalizedStringKey.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizedStringKey.StringInterpolation {
    /// Interpolates a string — mirrors SwiftUI's `appendInterpolation(_:)` for
    /// a `String`: `Text("Hello, \(name)!")`.
    ///
    /// The key holds `%@` where the string goes, in TUIkit's spelling and
    /// SwiftUI's alike, and the string is substituted as it is: it is not
    /// itself looked up.
    public mutating func appendInterpolation(_ string: String) {
        appendPlaceholder("%@")
        arguments.append(string)
    }

    /// Interpolates a substring, as a `String` — mirrors SwiftUI's
    /// `appendInterpolation(_:)` for a `Substring`.
    public mutating func appendInterpolation(_ substring: Substring) {
        appendInterpolation(String(substring))
    }

    /// Interpolates a number — mirrors SwiftUI's `appendInterpolation(_:)`
    /// for an integer or a floating-point number:
    /// `Text("Moved \(count) rows")`.
    ///
    /// The key holds `%@` where the number goes, and its `LocalizedStringKey.swiftUIKey`
    /// the number's own printf conversion (`%lld` for an `Int`, `%lf` for a
    /// `Double`), as SwiftUI's key does, so a String Catalog extracted from
    /// SwiftUI code is read; both are looked up.
    ///
    /// Drawn in the locale, as SwiftUI draws it (owner ruling B-TEXTFMT-1,
    /// 2026-10-24): grouped, with the locale's decimal separator —
    /// `1,234,567` and `3.5` in `en`, `1.234.567` and `3,5` in `de` — in
    /// `\.locale`: the app's locale, or the one a subtree sets for its
    /// `Text`s. **Not padded**, where SwiftUI's is: SwiftUI writes a `Double`
    /// through `%lf`, `3.500000`, which the owner ruled a bug not to mimic, so
    /// a floating-point number has at most `%lf`'s six fraction digits and no
    /// trailing zeros (`InterpolatedNumber`; Deliberate deviations T11).
    /// `\(value, specifier:)` writes exactly the conversion given.
    public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) {
        appendPlaceholder(value._specifier)
        let number = InterpolatedNumber(value)
        numberArguments[arguments.count] = number
        arguments.append(LocalizationService.shared.formatted(number))
    }

    /// Interpolates a `Text`, keeping its styling — mirrors SwiftUI, where
    /// this is how separately styled texts are joined:
    ///
    /// ```swift
    /// Text("Name: \(Text(person.name).bold()) \(Text("(edited)").italic())")
    /// ```
    ///
    /// A `Text` made from the key draws the interpolated one's runs where
    /// its placeholder stands, as SwiftUI does (measured 2026-10-18 on
    /// macOS 15: each such `Text` renders exactly as the deprecated
    /// `+` of its pieces). Its own attributes win, and what it leaves
    /// unset comes from around it: inside `**…**` an italic fragment is
    /// bold too, and a `.bold(false)` one stays plain; a modifier on the
    /// whole `Text` is the base beneath everything, so the fragment's own
    /// colour survives a `.foregroundStyle` on the whole.
    ///
    /// Anything else that takes the key — a button's title, a section
    /// header — reads the fragment's words, as it reads every argument.
    ///
    /// Without this overload the catch-all took `Text` too, and
    /// `String(describing:)`'d the whole struct — `Text(content: "Alice",
    /// style: …)` — into the sentence rather than reading its text. This
    /// overload is concrete where that one is generic, so it wins.
    ///
    /// A live `Text` — `Text(date, style: .relative)` — stays live: the
    /// key's text reads it again at each frame it is drawn in.
    public mutating func appendInterpolation(_ text: Text) {
        let index = arguments.count
        if let runs = text.runs, text.isLive {
            appendLive(TextRunsSource(runs: runs))
        } else {
            appendPlaceholder("%@")
            arguments.append(text.content)
        }
        if let styled = StyledArgument(text) { styledArguments[index] = styled }
    }

    /// Interpolates an `Image`, as SwiftUI's `Text` draws one inline: a
    /// system symbol as its glyph, and a picture as nothing.
    ///
    /// TUIkit's symbols are characters — `SFSymbol.glyph(named:)`, what
    /// `Image(systemName:)` draws — so a symbol has a plain-text form to
    /// substitute, where the catch-all `String(describing:)`'d the
    /// whole struct into the sentence. The glyph is the symbol's own, not a
    /// `symbolVariant` of it: the argument is substituted here, before any
    /// environment is known. A picture cannot sit in a line of text, so it
    /// contributes nothing rather than its description.
    public mutating func appendInterpolation(_ image: Image) {
        appendPlaceholder("%@")
        arguments.append(image.textGlyph)
    }

    /// Interpolates a number through a printf-style format specifier —
    /// mirrors SwiftUI's `appendInterpolation(_:specifier:)`:
    /// `Text("\(price, specifier: "%.2f")")`.
    ///
    /// Written exactly as the conversion writes it (`String(format:locale:)`)
    /// in the locale, like a bare number: `\.locale`, the app's where the key
    /// is built and a subtree's where its `Text` draws, so `%.2f` is `3.14` in
    /// `en` and `3,14` in `de`. The value is kept with the key
    /// (`InterpolatedNumber`), not only its text, and what the app's locale
    /// wrote is kept per number, as a bare number's is. The key carries `%@`
    /// where the value goes, like every other interpolation here, and its
    /// `swiftUIKey` the specifier itself, as SwiftUI's key does; both are
    /// looked up.
    ///
    /// - Parameters:
    ///   - value: The value to format.
    ///   - specifier: The format specifier, such as `%.2f` or `%x`.
    public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
        appendPlaceholder(specifier)
        let number = InterpolatedNumber(value, specifier: specifier)
        numberArguments[arguments.count] = number
        arguments.append(LocalizationService.shared.formatted(number))
    }

    /// Interpolates a value through a format style — the same eager
    /// formatting `Text(_:format:)` does.
    public mutating func appendInterpolation<F: FormatStyle>(
        _ value: F.FormatInput, format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == String {
        appendPlaceholder("%@")
        arguments.append(format.format(value))
    }

    /// Interpolates a value through a format style whose output is an
    /// `AttributedString` — its characters, formatted at once; every
    /// argument here is a plain string.
    public mutating func appendInterpolation<F: FormatStyle>(
        _ input: F.FormatInput, format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        appendPlaceholder("%@")
        arguments.append(String(format.format(input).characters))
    }

    /// The same, for a discrete style: the overload that makes
    /// `\(date, format: .offset(to: anchor))` TUIkit's `SystemFormatStyle`
    /// on macOS, where SwiftUI's statics are visible too (see
    /// `SystemFormatStyle+DiscreteStatics.swift`).
    @available(macOS 15, *)
    public mutating func appendInterpolation<F: DiscreteFormatStyle>(
        _ input: F.FormatInput, format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        appendPlaceholder("%@")
        arguments.append(String(format.format(input).characters))
    }

    /// Interpolates an attributed string, keeping its attributes — mirrors
    /// SwiftUI's `appendInterpolation(_:)` for an `AttributedString`.
    ///
    /// Taken as ``Text/init(_:)-(AttributedString)`` takes it and interpolated
    /// as that `Text` is: a `Text` made from the key draws its runs where its
    /// placeholder stands, and anything else that takes the key reads its
    /// characters.
    public mutating func appendInterpolation(_ attributedString: AttributedString) {
        // What `appendInterpolation(Text(attributedString))` does, without the
        // `Text`, whose initializer is the main actor's.
        if let runs = Text.styledRuns(of: attributedString) {
            styledArguments[arguments.count] = StyledArgument(runs: runs)
        }
        appendPlaceholder("%@")
        arguments.append(String(attributedString.characters))
    }

    /// Interpolates part of an attributed string, as an `AttributedString` —
    /// mirrors SwiftUI's `appendInterpolation(_:)` for an
    /// `AttributedSubstring`.
    public mutating func appendInterpolation(_ attributedSubstring: AttributedSubstring) {
        appendInterpolation(AttributedString(attributedSubstring))
    }

    /// Interpolates a Foundation value through a `Formatter` — mirrors
    /// SwiftUI's `appendInterpolation(_:formatter:)` for a
    /// `ReferenceConvertible` value: a `Date`, a `URL`, a `UUID`.
    ///
    /// Formatted at once, as every argument here is: the formatter's string
    /// for the value, or the value's description where the formatter gives
    /// none or there is no formatter. Only the formatting direction is used,
    /// which Foundation has on every platform; the parsing the `Formatter`
    /// forms of `TextField` would need is why those stay deferred (O11).
    ///
    /// - Parameters:
    ///   - subject: The value to format.
    ///   - formatter: The formatter to format it with, or `nil` for its
    ///     description.
    public mutating func appendInterpolation<Subject: ReferenceConvertible>(
        _ subject: Subject, formatter: Formatter? = nil
    ) {
        // Through a local `Any`, not `string(for: subject)`: handing a generic
        // `ReferenceConvertible` straight to the Objective-C `id` parameter
        // crashes SILGen on Darwin (Swift 6.2.4 to 6.4.0; reported as "SILGen
        // asserts (`isConcrete()`) passing a generic `ReferenceConvertible`
        // value to an Objective-C `id` parameter"), and `subject as Any` is
        // folded into the same conversion.
        let value: Any = subject
        appendInterpolation(formatter?.string(for: value) ?? String(describing: subject))
    }

    /// Interpolates a Foundation object through a `Formatter` — mirrors
    /// SwiftUI's `appendInterpolation(_:formatter:)` for an `NSObject`: an
    /// `NSNumber`, an `NSDate`. As the `ReferenceConvertible` form formats.
    ///
    /// - Parameters:
    ///   - subject: The object to format.
    ///   - formatter: The formatter to format it with, or `nil` for its
    ///     description.
    public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject, formatter: Formatter? = nil) {
        appendInterpolation(formatter?.string(for: subject) ?? String(describing: subject))
    }
}
