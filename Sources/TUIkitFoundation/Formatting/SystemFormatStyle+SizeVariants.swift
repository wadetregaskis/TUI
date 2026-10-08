//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemFormatStyle+SizeVariants.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@available(macOS 15, *)
extension SystemFormatStyle.DateOffset: DateSizeVariantFormatStyle {
    /// `1 hour, 2 minutes` → `1 hr, 2 min` → `1h 2m` (measured on macOS 15),
    /// signed as the widest is; a clock face (`2:05`) has no narrower one.
    func sizeVariants(of input: Date, locale: Locale) -> [String] {
        let styled = self.locale(locale)
        guard !styled.isClockFace else { return [String(styled.format(input).characters)] }
        let shown = styled.spelling.shown(styled.counted(input))
        let sign = styled.signPrefix(input)
        return [TimeSpanWidth.wide, .abbreviated, .narrow].map {
            sign + TimeSpan.unitList(shown, width: $0, locale: locale, calendar: calendar)
        }
    }
}

@available(macOS 15, *)
extension SystemFormatStyle.DateReference: DateSizeVariantFormatStyle {
    /// Relative, `2 minutes ago` → `2 min. ago` → `2m ago` (a named day,
    /// `yesterday`, has no narrower one); absolute, the three rungs of
    /// `absolute(_:rung:)`. Measured on macOS 15.
    func sizeVariants(of input: Date, locale: Locale) -> [String] {
        let styled = self.locale(locale)
        if styled.isRelative(input) {
            return [Date.RelativeFormatStyle.UnitsStyle.wide, .abbreviated, .narrow].map {
                styled.relative(input, units: $0)
            }
        }
        return (0...2).map { styled.absolute(input, rung: $0) }
    }
}

@available(macOS 15, *)
extension SystemFormatStyle.Stopwatch: DateSizeVariantFormatStyle {
    func sizeVariants(of input: Date, locale: Locale) -> [String] {
        face.sizeVariants(for: value(at: input), roundsUp: false, locale: locale)
    }
}

@available(macOS 15, *)
extension SystemFormatStyle.Timer: DateSizeVariantFormatStyle {
    func sizeVariants(of input: Date, locale: Locale) -> [String] {
        face.sizeVariants(for: value(at: input), roundsUp: countsDown, locale: locale)
    }
}
