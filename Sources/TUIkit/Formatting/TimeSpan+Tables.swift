//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimeSpan+Tables.swift
//
//  A span of a month or more spelt from the framework's own tables, for the
//  platforms whose Foundation cannot spell one (see `TimeSpan.unitList`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension TimeSpan {
    /// `fields` spelt as `Date.ComponentsFormatStyle` spells them on Apple
    /// platforms, without it: years and months from the framework's
    /// translation tables (`timeSpan.*` — the CLDR unit names, as Apple's
    /// Foundation draws them), every finer unit by `Duration.UnitsFormatStyle`
    /// one unit at a time, and the lot joined as `Duration.UnitsFormatStyle`
    /// joins units in `locale` (``unitSeparators(width:locale:)``).
    ///
    /// What the open-source Foundation spells a span of a month or more with
    /// — see the note on `calendarUnitList` in `TimeSpan.swift` for why.
    /// Compiled everywhere, so the Apple build can hold it to
    /// `Date.ComponentsFormatStyle`'s strings.
    ///
    /// A locale in none of the framework's seven languages takes English names
    /// in its own number format and its own joining.
    static func tableUnitList(_ fields: [TimeSpanField], width: TimeSpanWidth, locale: Locale) -> String {
        let names = fields.map { field -> String in
            guard let unit = field.unit.durationUnit, let seconds = field.unit.seconds else {
                return tableName(of: field, width: width, locale: locale)
            }
            return Duration.seconds(Int64(field.value) * seconds).formatted(
                unitsStyle([unit], count: 1, width: width, locale: locale))
        }
        guard names.count > 1 else { return names.first ?? "" }
        let separators = unitSeparators(width: width, locale: locale)
        guard names.count > 2 else { return names[0] + separators.pair + names[1] }
        return names.dropLast().joined(separator: separators.start) + separators.end + names[names.count - 1]
    }

    /// A year or month field's words, from the translation tables: the
    /// pattern for its unit, width and plural category, with the count in
    /// `locale`'s digits.
    ///
    /// The tables hold the wide and the abbreviated names; a condensed or a
    /// narrow width reads the abbreviated one (joined at its own width), so
    /// off Darwin a `.sizeDependent` text's narrowest rung spells a year or a
    /// month as its abbreviated rung does.
    static func tableName(of field: TimeSpanField, width: TimeSpanWidth, locale: Locale) -> String {
        let language = TimeSpanLanguage(locale).language
        let unit = field.unit == .year ? "year" : "month"
        let widthName = width == .wide ? "wide" : "abbreviated"
        let category = pluralCategory(of: field.value, in: language)
        let pattern = LocalizationService.shared.string(
            for: "timeSpan.\(unit).\(widthName).\(category)", in: language)
        return pattern.replacingOccurrences(
            of: "%@", with: field.value.formatted(IntegerFormatStyle<Int>(locale: locale)))
    }

    /// The CLDR plural category the tables are keyed by — `one` or `other` —
    /// for a whole count in `language`.
    ///
    /// French counts zero as one ("0 an"); Japanese and Chinese have no plural.
    /// CLDR's `many` (French, Italian and Spanish multiples of a million) is
    /// spelt as `other`: a span of a million years is not one a clock reads.
    static func pluralCategory(of count: Int, in language: LocalizationService.Language) -> String {
        switch language {
        case .japanese, .simplifiedChinese: return "other"
        case .french: return count == 0 || count == 1 ? "one" : "other"
        case .english, .german, .italian, .spanish: return count == 1 ? "one" : "other"
        }
    }

    /// The separators `Duration.UnitsFormatStyle` puts between units in
    /// `locale` at `width` — between a pair, after each but the last two of a
    /// longer list, and before its last — read off its own spelling of one,
    /// two and three units, so the joining is CLDR's unit list pattern exactly
    /// as the platform has it: `"1 Std., 2 Min. und 3 Sek."` gives `", "` and
    /// `" und "`; Japanese gives a space and Chinese nothing.
    ///
    /// `", "` where a spelling does not decompose as expected.
    static func unitSeparators(width: TimeSpanWidth, locale: Locale) -> (pair: String, start: String, end: String) {
        func spelt(_ seconds: Int64, _ units: Set<Duration.UnitsFormatStyle.Unit>) -> String {
            Duration.seconds(seconds).formatted(unitsStyle(units, count: units.count, width: width, locale: locale))
        }
        let hour = spelt(3_600, [.hours])
        let minutes = spelt(120, [.minutes])
        let seconds = spelt(3, [.seconds])
        func between(_ whole: String, _ first: String, _ last: String) -> Substring? {
            guard whole.hasPrefix(first), whole.hasSuffix(last), whole.count >= first.count + last.count else {
                return nil
            }
            return whole.dropFirst(first.count).dropLast(last.count)
        }
        let pair = between(spelt(3_720, [.hours, .minutes]), hour, minutes).map(String.init) ?? ", "
        guard let middle = between(spelt(3_723, [.hours, .minutes, .seconds]), hour, seconds),
            let found = middle.range(of: minutes)
        else { return (pair, pair, pair) }
        return (pair, String(middle[..<found.lowerBound]), String(middle[found.upperBound...]))
    }

    /// `Duration.UnitsFormatStyle` for `units`, showing `count` of them, zeros
    /// included, in whole units.
    static func unitsStyle(
        _ units: Set<Duration.UnitsFormatStyle.Unit>, count: Int, width: TimeSpanWidth, locale: Locale
    ) -> Duration.UnitsFormatStyle {
        Duration.UnitsFormatStyle(
            allowedUnits: units, width: width.durationWidth, maximumUnitCount: count,
            zeroValueUnits: .show(length: 1), valueLength: nil, fractionalPart: .hide
        ).locale(locale)
    }
}

/// Which of the framework's languages spells a locale's years and months.
struct TimeSpanLanguage {
    let language: LocalizationService.Language

    /// The locale's language, if the framework has it; English otherwise.
    /// Chinese written in Traditional characters takes English too, the
    /// framework's Chinese being Simplified.
    init(_ locale: Locale) {
        let code = locale.language.languageCode?.identifier ?? "en"
        let traditional = locale.language.script?.identifier == "Hant"
            || ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")
        if code == "zh", traditional {
            language = .english
        } else {
            language = LocalizationService.Language(rawValue: code) ?? .english
        }
    }
}
