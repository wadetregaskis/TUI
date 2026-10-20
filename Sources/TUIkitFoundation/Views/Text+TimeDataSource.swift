//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+TimeDataSource.swift
//
//  `Text(_:format:)` over a `TimeDataSource`: a value of the clock formatted
//  by a `DiscreteFormatStyle`, kept up to date at the instants the style says
//  its output changes. And `Text(_:format:)` for a style whose output is an
//  `AttributedString`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension Text {
    /// Creates a text view that displays the current system time as defined by
    /// the given format style, keeping the text up to date as time progresses —
    /// mirrors SwiftUI's `init(_:format:)` over a `TimeDataSource`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .offset(to: startDate))
    /// Text(.currentDate, format: .stopwatch(startingAt: startDate))
    /// ```
    ///
    /// The text formats the source's value when it is drawn, in the
    /// environment's `\.locale`, and asks the run loop for a frame at the
    /// instant the style's `discreteInput(after:)` names — so a reference that
    /// reads "in 5 minutes" is drawn again in a minute, not every frame. The
    /// output is drawn as the one-off `Text(_:format:)` draws it: any of
    /// SwiftUI's attributes a style sets show, at every frame, and Foundation's
    /// own field attributes are ignored as SwiftUI ignores them (decisions
    /// B88).
    ///
    /// SwiftUI's reduced-luminance redaction has nothing to act on in a
    /// terminal, which has no always-on display.
    ///
    /// - Parameters:
    ///   - source: The source of the value to format, such as `.currentDate`.
    ///   - format: The discrete format style to format it with.
    public init<V, F>(_ source: TimeDataSource<V>, format: F)
    where V == F.FormatInput, F: DiscreteFormatStyle, F.FormatOutput == AttributedString {
        self.init(
            live: FormattedTimeSource(
                source: source, format: format, output: { String($0.characters) }, styledOutput: Self.styledRuns(of:)))
    }

    /// Creates a text view that displays the current system time as defined by
    /// the given format style, keeping the text up to date as time progresses —
    /// mirrors SwiftUI's `init(_:format:)` over a `TimeDataSource`, for a style
    /// that formats into a `String`.
    ///
    /// ```swift
    /// Text(.currentDate, format: .dateTime)
    /// Text(.durationOffset(to: startDate), format: .time(pattern: .minuteSecond))
    /// ```
    ///
    /// - Parameters:
    ///   - source: The source of the value to format, such as `.currentDate`.
    ///   - format: The discrete format style to format it with.
    public init<V, F>(_ source: TimeDataSource<V>, format: F)
    where V == F.FormatInput, F: DiscreteFormatStyle, F.FormatOutput == String {
        self.init(live: FormattedTimeSource(source: source, format: format) { $0 })
    }
}

extension Text {
    /// Creates a text view that displays the formatted representation of a
    /// nonstring type supported by a corresponding format style — mirrors
    /// SwiftUI's `init(_:format:)` for a style whose output is an
    /// `AttributedString`.
    ///
    /// ```swift
    /// Text(deadline, format: .offset(to: start))
    /// ```
    ///
    /// Formatted eagerly, as the `String` form is (see that initialiser), and
    /// drawn as ``init(_:)-(AttributedString)`` draws the output: any of
    /// SwiftUI's attributes a style sets — a colour, a font — show, and
    /// Foundation's own field attributes, which say what a run IS rather than
    /// how it looks, are ignored as SwiftUI ignores them.
    ///
    /// - Parameters:
    ///   - input: The underlying value to display.
    ///   - format: A format style that converts `input` into an attributed
    ///     string.
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F)
    where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        self.init(format.format(input))
    }

    /// The same, for a discrete style — so that `.offset(to:)` and the other
    /// `SystemFormatStyle` statics here are TUIkit's on macOS, where SwiftUI's
    /// are visible too (see `SystemFormatStyle+DiscreteStatics.swift`).
    ///
    /// - Parameters:
    ///   - input: The underlying value to display.
    ///   - format: A discrete format style that converts `input` into an
    ///     attributed string.
    @available(macOS 15, *)
    public init<F: DiscreteFormatStyle>(_ input: F.FormatInput, format: F)
    where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        self.init(format.format(input))
    }
}

// MARK: - Source

/// A time data source's value through a discrete format style.
///
/// `@unchecked Sendable` because `FormatStyle` does not refine `Sendable`
/// while every format style is a value; the source holds one and never shares
/// mutable state.
@available(macOS 15, *)
struct FormattedTimeSource<Value, Format: DiscreteFormatStyle>: LiveTextSource, @unchecked Sendable
where Format.FormatInput == Value {
    let source: TimeDataSource<Value>
    let format: Format
    let output: @Sendable (Format.FormatOutput) -> String
    /// The output's styled runs, for a style whose output is attributed; `nil`
    /// for a plain one, or for an output with no look of its own.
    let styledOutput: (@Sendable (Format.FormatOutput) -> [Text.Run]?)?

    init(
        source: TimeDataSource<Value>, format: Format, output: @escaping @Sendable (Format.FormatOutput) -> String,
        styledOutput: (@Sendable (Format.FormatOutput) -> [Text.Run]?)? = nil
    ) {
        self.source = source
        self.format = format
        self.output = output
        self.styledOutput = styledOutput
    }

    func text(at date: Date, in environment: LiveTextEnvironment) -> String {
        output(format.locale(environment.locale).format(source.read(date)))
    }

    func runs(at date: Date, in environment: LiveTextEnvironment) -> [Text.Run]? {
        styledOutput.flatMap { $0(format.locale(environment.locale).format(source.read(date))) }
    }

    /// The instant the style's next input falls at — a second from now if a
    /// style names one that is not ahead, so a wrong boundary costs a frame a
    /// second rather than a frame every frame.
    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date? {
        let styled = format.locale(environment.locale)
        let value = source.read(date)
        guard let next = source.risesWithTime ? styled.discreteInput(after: value) : styled.discreteInput(before: value)
        else { return nil }
        let instant = source.instant(next)
        return instant > date ? instant : date.addingTimeInterval(1)
    }

    func isEqual(to other: any LiveTextSource) -> Bool {
        guard let other = other as? Self else { return false }
        return other.source.kind == source.kind && other.format == format
    }

    /// The format's ladder, where it is one of TUIkit's date styles that has
    /// one; else the one spelling.
    func sizeVariants(at date: Date, in environment: LiveTextEnvironment) -> [String] {
        guard let ladder = format as? any DateSizeVariantFormatStyle, let input = source.read(date) as? Date else {
            return [text(at: date, in: environment)]
        }
        return ladder.sizeVariants(of: input, locale: environment.locale)
    }
}
