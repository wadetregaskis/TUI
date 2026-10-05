//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClockFace.swift
//
//  The reading on a timer or a stopwatch — `1:02:05`, `00:05.25`, or
//  `1 hour, 2 minutes` when the face cannot hold it — and the value at which
//  it next changes. Shared by `SystemFormatStyle.Timer` and `.Stopwatch`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// SwiftUI's rules for a timer's and a stopwatch's face, measured on macOS 15
/// and pinned in `SystemFormatStyleClockTests`:
///
/// - The face is `m:ss`, or `h:mm:ss` from an hour when `showsHours`; a
///   stopwatch pads its leading field to two digits (`00:05`, `01:02:05`).
/// - Those are two or three fields; a fraction of a second is one more, shown
///   when the precision is finer than a second and `maxFieldCount` leaves room
///   — one digit to a tenth, two below (never three).
/// - A reading the face cannot hold in `maxFieldCount` fields is spelt in
///   units instead, truncated: `1 hour, 2 minutes`. So is any reading whose
///   precision is coarser than a second, without its seconds: `0 minutes`.
/// - On the face, a countdown rounds up to its precision and everything else
///   rounds down.
struct ClockFace: Sendable {
    let showsHours: Bool
    let maxFieldCount: Int
    /// The precision, in seconds.
    let precision: Double
    /// Whether the leading field takes two digits, as a stopwatch's does.
    let padsLeading: Bool

    /// Below anything a `Date` distinguishes at today's distance from the
    /// reference date (about 1.2e-7 s), so a value a hair short of a boundary
    /// through `Date` arithmetic still reaches it.
    private static let slack = 1e-6

    /// How a reading is shown.
    enum Shape: Equatable {
        /// On the face, in whole steps of `stepUnits` units, `scale` units to
        /// the second (1, 10 or 100), with `digits` fractional digits.
        case face(stepUnits: Int, scale: Int, digits: Int)
        /// In units, truncated.
        case units([TimeSpanUnit])
    }

    init(showsHours: Bool, maxFieldCount: Int, precision: Duration, padsLeading: Bool) {
        self.showsHours = showsHours
        self.maxFieldCount = max(1, maxFieldCount)
        let components = precision.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        self.precision = seconds > 0 ? seconds : 0.01
        self.padsLeading = padsLeading
    }

    /// How `value` seconds is shown, rounded up (`roundsUp`) or down.
    func shape(for value: Double, roundsUp: Bool) -> Shape {
        let units: [TimeSpanUnit] = showsHours ? [.hour, .minute, .second] : [.minute, .second]
        guard precision <= 1 + Self.slack else { return .units(units.filter { $0 != .second }) }
        let whole = roundsUp ? (value - Self.slack).rounded(.up) : (value + Self.slack).rounded(.down)
        let fields = showsHours && whole >= 3_600 ? 3 : 2
        guard fields <= maxFieldCount else { return .units(units) }
        guard precision < 1 - Self.slack, fields < maxFieldCount else {
            return .face(stepUnits: 1, scale: 1, digits: 0)
        }
        let digits = precision >= 0.1 - Self.slack ? 1 : 2
        let scale = digits == 1 ? 10 : 100
        return .face(stepUnits: max(1, Int((precision * Double(scale)).rounded())), scale: scale, digits: digits)
    }

    /// `value` seconds, quantised to `stepUnits` units of `1/scale` second.
    private func quantised(_ value: Double, stepUnits: Int, scale: Int, roundsUp: Bool) -> Int {
        let steps = value * Double(scale) / Double(stepUnits)
        let rounded = roundsUp ? (steps - Self.slack).rounded(.up) : (steps + Self.slack).rounded(.down)
        return max(0, Int(rounded)) * stepUnits
    }

    /// The fields `value` seconds is counted in, in `units`, truncated: from
    /// the first that is not zero, `maxFieldCount` of them, zeros shown (a
    /// timer reads under a day). The first unit takes as many as there are:
    /// a timer has no days.
    private func counted(_ value: Double, in units: [TimeSpanUnit]) -> [TimeSpanField] {
        var remaining = max(0, Int((value + Self.slack).rounded(.down)))
        var values: [Int] = []
        for unit in units {
            let length = Int(unit.seconds ?? 1)
            values.append(remaining / length)
            remaining %= length
        }
        guard let first = values.firstIndex(where: { $0 != 0 }) else {
            return [TimeSpanField(unit: units.last ?? .second, value: 0)]
        }
        let end = min(units.count, first + maxFieldCount)
        return (first..<end).map { TimeSpanField(unit: units[$0], value: values[$0]) }
    }

    /// The face's spellings of `value` seconds, widest first, for a
    /// `.sizeDependent` text (decisions A32, measured on macOS 15):
    ///
    /// - in units, `1 hour, 2 minutes` → `1 hr 2 min` → `1:02`;
    /// - a stopwatch's padded face, `01:02:05.50` → `1:02:05` → `1:02` → `1h`,
    ///   each dropping what the last kept: the fraction and the padding, the
    ///   seconds, then all but the leading field, in its narrowest unit;
    /// - a timer's face, `1:02:05`, has no narrower spelling.
    func sizeVariants(for value: Double, roundsUp: Bool, locale: Locale) -> [String] {
        let widest = text(for: value, roundsUp: roundsUp, locale: locale)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        switch shape(for: value, roundsUp: roundsUp) {
        case .units(let units):
            let fields = counted(value, in: units)
            var ladder = [widest]
            ladder.append(TimeSpan.unitList(fields, width: .condensedAbbreviated, locale: locale, calendar: calendar))
            if fields.count > 1 {
                ladder.append(
                    ([String(fields[0].value)] + fields.dropFirst().map { $0.value < 10 ? "0\($0.value)" : "\($0.value)" })
                        .joined(separator: ":"))
            }
            return ladder
        case .face:
            guard padsLeading else { return [widest] }
            let whole = Int((value + Self.slack).rounded(.down))
            var ladder = [widest, TimeSpan.clock(seconds: whole, showsHours: showsHours, padsLeading: false)]
            let hours = showsHours ? whole / 3_600 : 0
            if hours > 0 {
                let minutes = whole / 60 % 60
                ladder.append("\(hours):\(minutes < 10 ? "0" : "")\(minutes)")
            }
            let leading: TimeSpanField =
                hours > 0
                ? TimeSpanField(unit: .hour, value: hours)
                : whole >= 60 ? TimeSpanField(unit: .minute, value: whole / 60) : TimeSpanField(unit: .second, value: whole)
            ladder.append(TimeSpan.unitList([leading], width: .narrow, locale: locale, calendar: calendar))
            return ladder
        }
    }

    /// What the face reads for `value` seconds.
    func text(for value: Double, roundsUp: Bool, locale: Locale) -> String {
        switch shape(for: value, roundsUp: roundsUp) {
        case .face(let stepUnits, let scale, let digits):
            let total = quantised(value, stepUnits: stepUnits, scale: scale, roundsUp: roundsUp)
            let clock = TimeSpan.clock(seconds: total / scale, showsHours: showsHours, padsLeading: padsLeading)
            guard digits > 0 else { return clock }
            let fraction = String(total % scale)
            return clock + "." + String(repeating: "0", count: digits - fraction.count) + fraction
        case .units(let units):
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            return TimeSpan.unitList(counted(value, in: units), width: .wide, locale: locale, calendar: calendar)
        }
    }

    /// Where a reading changes, as a VALUE: the value, and whether the change
    /// happens at it (`.at`) or just past it in the direction travelled.
    enum Boundary: Equatable {
        case at(Double)
        case justPast(Double)
    }

    /// The next value at which the reading of `value` changes, travelling
    /// `increasing` (or decreasing) — `nil` past `limit` (or below zero).
    func next(after value: Double, increasing: Bool, roundsUp: Bool, limit: Double) -> Boundary? {
        switch shape(for: value, roundsUp: roundsUp) {
        case .face(let stepUnits, let scale, _):
            let step = Double(stepUnits) / Double(scale)
            let current = Double(quantised(value, stepUnits: stepUnits, scale: scale, roundsUp: roundsUp)) / Double(scale)
            if increasing {
                // Rounding down, the reading is `k` until the value reaches
                // `k + step`; rounding up, it is `k` until it passes `k` —
                // which a value already at its limit never does.
                if roundsUp {
                    guard current < limit - Self.slack else { return nil }
                    return .justPast(current)
                }
                guard current + step <= limit + Self.slack else { return nil }
                return .at(current + step)
            }
            // Rounding up, the reading is `k` until the value falls to
            // `k − step`; rounding down, until it falls below `k` — which a
            // reading of nothing never does.
            if roundsUp {
                guard current - step >= -Self.slack else { return nil }
                return .at(current - step)
            }
            guard current > Self.slack else { return nil }
            return .justPast(current)
        case .units(let units):
            let fields = counted(value, in: units)
            let finest = Double(fields.last?.unit.seconds ?? 1)
            let total = fields.reduce(0.0) { $0 + Double($1.value) * Double($1.unit.seconds ?? 1) }
            if increasing {
                guard total + finest <= limit + Self.slack else { return nil }
                return .at(total + finest)
            }
            guard total > Self.slack else { return nil }
            return .justPast(total)
        }
    }
}
