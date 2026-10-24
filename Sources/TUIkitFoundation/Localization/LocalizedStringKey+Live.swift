//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKey+Live.swift
//
//  The interpolations that read the clock — `\(date, style: .relative)`,
//  `\(timerInterval: start...end)`, an interpolated live `Text` — and the
//  source a `Text` made from such a key reads them through.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizedStringKey.StringInterpolation {
    /// Appends a formatted date to a string interpolation — mirrors SwiftUI's
    /// `appendInterpolation(_:style:)`.
    ///
    /// ```swift
    /// Text("Ends \(deadline, style: .relative) from now")
    /// ```
    ///
    /// The `Text` the key makes keeps the date live, as `Text(_:style:)`
    /// does: it reads it again at each frame it is drawn, and asks for a frame
    /// at each change. So do the controls that draw a title key as its `Text`
    /// — a button's and a colour picker's title, a field's placeholder, a
    /// toggle's label — and a table column's header (B51-LIVE). What takes the
    /// key only for its string — a navigation title, an alert's title, as
    /// SwiftUI's do (measured) — reads it once, when it is built.
    ///
    /// - Parameters:
    ///   - date: The date to append.
    ///   - style: A predefined style to format the date with.
    public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
        appendLive(DateStyleSource(date: date, style: style))
    }

    /// Appends a timer interval to a string interpolation — mirrors SwiftUI's
    /// `appendInterpolation(timerInterval:pauseTime:countsDown:showsHours:)`.
    ///
    /// ```swift
    /// Text("Left: \(timerInterval: start...end)")
    /// ```
    ///
    /// Live in a `Text` the same way ``appendInterpolation(_:style:)`` is; see
    /// `Text(timerInterval:pauseTime:countsDown:showsHours:)` for the readings.
    ///
    /// - Parameters:
    ///   - timerInterval: The interval between where to run the timer.
    ///   - pauseTime: If present, the date at which to pause the timer. The
    ///     default is `nil`, which never pauses.
    ///   - countsDown: Whether to count up or down. The default is `true`.
    ///   - showsHours: Whether to include an hours component if there are more
    ///     than 60 minutes left on the timer. The default is `true`.
    public mutating func appendInterpolation(
        timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        appendLive(
            TimerIntervalSource(
                start: timerInterval.lowerBound, end: timerInterval.upperBound, pauseTime: pauseTime,
                countsDown: countsDown, showsHours: showsHours))
    }

    /// Appends a time data source's value through a discrete format style,
    /// kept up to date — mirrors SwiftUI's `appendInterpolation(_:format:)`
    /// over a `TimeDataSource`.
    ///
    /// ```swift
    /// Text("Started \(.currentDate, format: .offset(to: start))")
    /// ```
    ///
    /// Live in the `Text` the key makes, as `Text(_:format:)` over the source
    /// is, and read once, when built, by anything else that takes the key. An
    /// attributed output contributes its characters, as every interpolated
    /// format does (decisions B88).
    ///
    /// - Parameters:
    ///   - source: The source of the value to format, such as `.currentDate`.
    ///   - format: The discrete format style to format it with.
    @available(macOS 15, *)
    public mutating func appendInterpolation<V, F>(_ source: TimeDataSource<V>, format: F)
    where V == F.FormatInput, F: DiscreteFormatStyle, F.FormatOutput == AttributedString {
        appendLive(FormattedTimeSource(source: source, format: format) { String($0.characters) })
    }

    /// The same, for a style that formats into a `String` — disfavoured, as
    /// SwiftUI's is, so that a style with both outputs is the attributed one.
    ///
    /// - Parameters:
    ///   - source: The source of the value to format, such as `.currentDate`.
    ///   - format: The discrete format style to format it with.
    @available(macOS 15, *)
    @_disfavoredOverload
    public mutating func appendInterpolation<V, F>(_ source: TimeDataSource<V>, format: F)
    where V == F.FormatInput, F: DiscreteFormatStyle, F.FormatOutput == String {
        appendLive(FormattedTimeSource(source: source, format: format) { $0 })
    }

    /// Appends an argument that reads the clock: a `%@` in the key, its reading
    /// now as the argument everything but a `Text` uses, and the source beside
    /// it for the `Text`.
    mutating func appendLive(_ source: some LiveTextSource) {
        appendPlaceholder("%@")
        liveArguments[arguments.count] = LiveTextBox(source)
        arguments.append(source.text(at: Date(), in: .current))
    }
}

// MARK: - Sources

/// A key with live arguments, as a `Text` made from it reads it: the key looked
/// up as it always is, with each live argument read at the frame's date.
struct LocalizedKeySource: LiveTextSource, Equatable {
    let key: LocalizedStringKey
    /// The string table the key is read from where TUIkit's dictionaries miss
    /// it, as `Text(_:tableName:bundle:comment:)` named it.
    var tableName: String?
    var bundle: Bundle?
    /// The language a subtree's `\.locale` named, where the key is read in
    /// that one first (``Text/relocalized(in:)``); `nil` for the app's.
    var language: String?

    /// The key's template, read where the `Text` reads it.
    private var template: String {
        LocalizationService.shared.reading(
            key.key, swiftUIKey: key.swiftUIKey, tableName: tableName, bundle: bundle, in: language
        ).text
    }

    func text(at date: Date, in environment: LiveTextEnvironment) -> String {
        var arguments = key.arguments
        for (index, live) in key.liveArguments where arguments.indices.contains(index) {
            arguments[index] = live.source.text(at: date, in: environment)
        }
        let template = template
        return arguments.isEmpty ? template : LocalizedStringKey.substituting(arguments, into: template)
    }

    /// Each live argument's ladder, substituted rung by rung.
    func sizeVariants(at date: Date, in environment: LiveTextEnvironment) -> [String] {
        let template = template
        let ladders = key.arguments.indices.map { index -> [String] in
            guard let live = key.liveArguments[index] else { return [key.arguments[index]] }
            return live.source.sizeVariants(at: date, in: environment)
        }
        guard !ladders.isEmpty else { return [template] }
        return zippedSizeVariants(ladders) { LocalizedStringKey.substituting($0, into: template) }
    }

    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date? {
        key.liveArguments.values.compactMap { $0.source.nextChange(after: date, in: environment) }.min()
    }
}

/// An interpolated live `Text`, as its runs read: its plain fragments as they
/// are, its live ones at the frame's date. The text's styling is not carried —
/// an interpolation's every argument is a plain string.
struct TextRunsSource: LiveTextSource, Equatable {
    let runs: [Text.Run]

    func text(at date: Date, in environment: LiveTextEnvironment) -> String {
        runs.map { $0.live?.source.text(at: date, in: environment) ?? $0.text }.joined()
    }

    /// Each live run's ladder, joined rung by rung.
    func sizeVariants(at date: Date, in environment: LiveTextEnvironment) -> [String] {
        zippedSizeVariants(runs.map { $0.live?.source.sizeVariants(at: date, in: environment) ?? [$0.text] }) {
            $0.joined()
        }
    }

    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date? {
        runs.compactMap { $0.live?.source.nextChange(after: date, in: environment) }.min()
    }
}
