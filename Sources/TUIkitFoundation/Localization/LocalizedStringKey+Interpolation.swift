//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKey+Interpolation.swift
//
//  The typed interpolations of a `LocalizedStringKey`: an interpolated `Text`
//  or `Image`, a number through a printf specifier, a value through a format
//  style. The clock-reading ones are in `LocalizedStringKey+Live.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizedStringKey.StringInterpolation {
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
    /// Formatted at once, in the current locale, as `Text(_:format:)`
    /// formats. The key carries `%@` where the value goes, like every other
    /// interpolation here, and its `swiftUIKey` the
    /// specifier itself, as SwiftUI's key does; both are looked up.
    ///
    /// - Parameters:
    ///   - value: The value to format.
    ///   - specifier: The format specifier, such as `%.2f` or `%x`.
    public mutating func appendInterpolation<T: CVarArg>(_ value: T, specifier: String) {
        appendPlaceholder(specifier)
        arguments.append(String(format: specifier, locale: .current, value))
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
}
