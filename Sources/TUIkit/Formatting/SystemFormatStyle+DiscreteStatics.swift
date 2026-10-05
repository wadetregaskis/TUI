//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+DiscreteStatics.swift
//
//  The `.timer`, `.stopwatch`, `.offset` and `.reference` statics a second
//  time, on `DiscreteFormatStyle`, so that SwiftUI's own — which reach every
//  module on macOS that imports AppKit — do not take their place in a `Text`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// Why these exist.
//
// From the macOS 15 SDK on AppKit imports SwiftUICore. Before Swift's
// member-import-visibility rule (an upcoming feature an app must opt into), an
// EXTENSION member of any module a module imports, however indirectly, is
// visible to it — so a module that imports AppKit sees SwiftUICore's
// `FormatStyle.offset(to:…)` and the other three beside TUIkit's. The TYPES do
// not leak, only the extension members, and these four are extension members
// of Foundation's `FormatStyle`.
//
// TUIkit itself no longer imports AppKit (decisions B50): its bridges to
// `NSColor` and the rest are the `TUIkitAppKit` module, and an app that imports
// only TUIkit sees TUIkit's statics alone — `Date.now.formatted(.offset(to:
// d))` compiles, as `CompileCorpusTUIkitOnly.swift` proves. But an app that
// imports `TUIkitAppKit`, or AppKit itself, loads SwiftUICore again, and for it
// what follows still holds. So the second declaration stays: re-measured
// 2026-10-05 with a three-module probe (a library with no AppKit, a bridge
// module importing it, and two clients), a single declaration on `FormatStyle`
// works for the client of the library alone and is AMBIGUOUS in a
// `DiscreteFormatStyle` context for the client of both; the pair works for both.
//
// Measured with a two-module probe (W11a notes, `ambig/`):
//
// - Where both are on `FormatStyle`, `.offset(to:)` is AMBIGUOUS in any
//   context that accepts a `FormatStyle` — `Text(.currentDate, format:
//   .offset(to: d))` failed to compile.
// - With TUIkit's only on `DiscreteFormatStyle`, a context accepting any
//   `FormatStyle` picks SwiftUI's, which then fails to LINK: SwiftUICore
//   refuses direct clients.
// - With TUIkit's on both, a `DiscreteFormatStyle` context picks the one here
//   — an extension of the refining protocol is the more specialised — and a
//   plain `FormatStyle` context is ambiguous, a compile error rather than a
//   link error.
//
// So TUIkit declares both, and every TUIkit API that takes these styles takes
// a `DiscreteFormatStyle` (adding that overload beside the `FormatStyle` one
// where SwiftUI has only the latter). What stays ambiguous, in an app that
// imports AppKit, is a `FormatStyle` context outside TUIkit —
// `Date.now.formatted(.offset(to: d))` — where spelling the type
// (`SystemFormatStyle.DateOffset(to: d)`) settles it. On Linux there is no
// SwiftUICore and nothing collides.

@available(macOS 15, *)
extension DiscreteFormatStyle where Self == SystemFormatStyle.Timer {
    /// Create a timer format style that counts down in the given interval.
    ///
    /// The same as `FormatStyle`'s `.timer(countingDownIn:…)`; see this file
    /// for why it is declared twice.
    ///
    /// - Parameters:
    ///   - interval: The interval during which the timer counts down.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func timer(
        countingDownIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
        maxPrecision: Duration = .seconds(1)
    ) -> SystemFormatStyle.Timer {
        SystemFormatStyle.Timer(
            countingDownIn: interval, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }

    /// Create a timer format style that counts up in the given interval.
    ///
    /// The same as `FormatStyle`'s `.timer(countingUpIn:…)`.
    ///
    /// - Parameters:
    ///   - interval: The interval during which the timer counts up.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func timer(
        countingUpIn interval: Range<Date>, showsHours: Bool = true, maxFieldCount: Int = 3,
        maxPrecision: Duration = .seconds(1)
    ) -> SystemFormatStyle.Timer {
        SystemFormatStyle.Timer(
            countingUpIn: interval, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }
}

@available(macOS 15, *)
extension DiscreteFormatStyle where Self == SystemFormatStyle.Stopwatch {
    /// Create a stopwatch format style.
    ///
    /// The same as `FormatStyle`'s `.stopwatch(startingAt:…)`.
    ///
    /// - Parameters:
    ///   - startDate: The date at which the stopwatch starts counting.
    ///   - showsHours: Whether the hours are a field of their own from an hour.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - maxPrecision: The precision the input is formatted at.
    public static func stopwatch(
        startingAt startDate: Date, showsHours: Bool = true, maxFieldCount: Int = 4,
        maxPrecision: Duration = .milliseconds(10)
    ) -> SystemFormatStyle.Stopwatch {
        SystemFormatStyle.Stopwatch(
            startingAt: startDate, showsHours: showsHours, maxFieldCount: maxFieldCount, maxPrecision: maxPrecision)
    }
}

@available(macOS 15, *)
extension DiscreteFormatStyle where Self == SystemFormatStyle.DateOffset {
    /// Create a format style to display the offset to a certain date.
    ///
    /// The same as `FormatStyle`'s `.offset(to:…)`.
    ///
    /// - Parameters:
    ///   - anchor: The date the offset is measured to from the format input.
    ///   - allowedFields: The units of time that may be used.
    ///   - maxFieldCount: The number of fields that can be shown at once.
    ///   - sign: Whether the offset is signed.
    public static func offset(
        to anchor: Date,
        allowedFields: Set<Date.ComponentsFormatStyle.Field> = [.year, .month, .day, .hour, .minute, .second],
        maxFieldCount: Int = 2, sign: NumberFormatStyleConfiguration.SignDisplayStrategy = .automatic
    ) -> SystemFormatStyle.DateOffset {
        SystemFormatStyle.DateOffset(to: anchor, allowedFields: allowedFields, maxFieldCount: maxFieldCount, sign: sign)
    }
}

@available(macOS 15, *)
extension DiscreteFormatStyle where Self == SystemFormatStyle.DateReference {
    /// Create a format style to refer to a date in the most natural way.
    ///
    /// The same as `FormatStyle`'s `.reference(to:…)`.
    ///
    /// - Parameters:
    ///   - date: The date this format references.
    ///   - allowedFields: The units of time that may be used.
    ///   - maxFieldCount: The number of fields shown at once in the absolute
    ///     form.
    ///   - thresholdField: The least precise field the relative form may use.
    public static func reference(
        to date: Date, allowedFields: Set<Date.RelativeFormatStyle.Field> = [.year, .month, .day, .hour, .minute],
        maxFieldCount: Int = 2, thresholdField: Date.RelativeFormatStyle.Field = .day
    ) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(
            to: date, allowedFields: allowedFields, maxFieldCount: maxFieldCount, thresholdField: thresholdField)
    }
}
