//  🖥️ TUI — A Terminal UI framework for Swift
//  InterpolatedNumber.swift
//
//  A number interpolated into a localized string's key —
//  `Text("\(count) rows")`, or with a specifier, `Text("\(price, specifier:
//  "%.2f")")` — and how it is written in a locale (owner ruling B-TEXTFMT-1,
//  2026-10-24).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A number interpolated into a `LocalizedStringKey`, kept with the key so it
/// can be written in whichever locale the key is read in.
///
/// Written as `.number` writes it (``formatted(in:)``): grouped as the locale
/// groups, with its decimal separator, and a floating-point number to at most
/// six fraction digits with no trailing zeros — `1,234,567`, `3.5`, `0.3` in
/// `en`; `1.234.567`, `3,5` in `de`; `1 234 567` with a narrow no-break
/// space in `fr`.
///
/// SwiftUI writes the number through its printf conversion (`%lld`, `%lf`)
/// in the locale, which pads a `Double` to six fraction digits, `3.500000`;
/// the owner ruled that padding a bug not to mimic. Six digits at most is
/// `%lf`'s precision, so what is drawn is SwiftUI's number with the trailing
/// zeros dropped — not the shortest form that round-trips, which writes
/// `0.1 + 0.2` as `0.30000000000000004` (Deliberate deviations T11).
///
/// A number interpolated **with** a specifier, `\(price, specifier: "%.2f")`,
/// is written by exactly that conversion (``specified(_:_:)``), through
/// `String(format:locale:)` in the locale: `3.14` in `en`, `3,14` in `de`.
package enum InterpolatedNumber: Hashable, Sendable {
    /// A signed integer, widened.
    case signed(Int64)
    /// An unsigned integer, widened.
    case unsigned(UInt64)
    /// A floating-point number, by its `Double`'s bits: so a NaN is equal to
    /// itself, as a memo's key must be, and `-0`, written `-0`, is kept apart
    /// from `0`.
    case floating(bitPattern: UInt64)
    /// A number of a type outside the standard library's and `CGFloat`, which
    /// only a conformance to `_FormatSpecifiable` of an app's own makes (its
    /// underscore says not to): its description, in every locale.
    case verbatim(String)
    /// A number of the standard library's or `CGFloat`, with the printf
    /// conversion the interpolation named — `%.2f`, `%x` — written exactly as
    /// that conversion writes it in the locale (no grouping, no trimming).
    case specified(String, Argument)

    /// What a printf conversion is given, at the width C's variadic promotion
    /// gives it: `%d` reads an `Int32`, `%lld` an `Int64`, and `%f` a `Double`
    /// (which a `Float` and a `CGFloat` are widened to).
    package enum Argument: Hashable, Sendable {
        case int32(Int32)
        case int64(Int64)
        case uint32(UInt32)
        case uint64(UInt64)
        /// By its bits, as ``floating(bitPattern:)`` keeps a `Double`.
        case double(bitPattern: UInt64)

        /// The value as `String(format:locale:)` takes it.
        fileprivate var cVarArg: any CVarArg {
            switch self {
            case .int32(let value): value
            case .int64(let value): value
            case .uint32(let value): value
            case .uint64(let value): value
            case .double(let bits): Double(bitPattern: bits)
            }
        }

        /// Whether this is an unsigned value its signed twin cannot hold.
        fileprivate var exceedsSignedRange: Bool {
            switch self {
            case .uint32(let value): value > UInt32(Int32.max)
            case .uint64(let value): value > UInt64(Int64.max)
            case .int32, .int64, .double: false
            }
        }
    }

    /// A floating-point number.
    package init(_ value: Double) {
        self = .floating(bitPattern: value.bitPattern)
    }

    /// The number as `locale` writes it: `.number`'s style in that locale.
    ///
    /// About 0.3 µs each on an M-series Mac (measured 2026-10-24, 200,000
    /// calls; Foundation keeps the ICU formatter per style and locale), where
    /// `String(format:locale:)` with the printf conversion took 3.6 µs for an
    /// integer and 13 µs for a `Double`. ``LocalizationService/formatted(_:)``
    /// keeps what it writes in the app's locale, so a body that interpolates
    /// an unchanged number pays a lookup.
    package func formatted(in locale: Locale) -> String {
        switch self {
        case .signed(let value): IntegerFormatStyle<Int64>(locale: locale).format(value)
        case .unsigned(let value): IntegerFormatStyle<UInt64>(locale: locale).format(value)
        case .floating(let bits): FloatingPointFormatStyle<Double>(locale: locale).format(Double(bitPattern: bits))
        case .verbatim(let description): description
        case .specified(let specifier, let argument):
            #if canImport(Darwin)
                String(format: specifier, locale: locale, argument.cVarArg)
            #else
                // Outside Apple's platforms Foundation writes an integer in a
                // locale as signed: UInt.max came out "-1" (Swift 6.2 and 6.3
                // on Linux, CI, 2026-10-29). Without a locale it is right, and
                // that Foundation groups no conversion's digits either way.
                if argument.exceedsSignedRange {
                    String(format: specifier, argument.cVarArg)
                } else {
                    String(format: specifier, locale: locale, argument.cVarArg)
                }
            #endif
        }
    }
}
