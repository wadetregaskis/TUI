import Foundation

// What Foundation's own formatters produce for the strings SwiftUI's live text
// shows, on macOS 15: the candidates for reproducing them.
let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
func at(_ s: Double) -> Date { base.addingTimeInterval(s) }
let en = Locale(identifier: "en_US")
let de = Locale(identifier: "de_DE")
var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func units(_ secs: Int64, _ allowed: Set<Duration.UnitsFormatStyle.Unit>, _ width: Duration.UnitsFormatStyle.UnitWidth, max: Int, zero: Duration.UnitsFormatStyle.ZeroValueUnitsDisplayStrategy = .hide, locale: Locale = en) -> String {
    Duration.seconds(secs).formatted(Duration.UnitsFormatStyle(allowedUnits: allowed, width: width, maximumUnitCount: max, zeroValueUnits: zero, valueLength: nil, fractionalPart: .hide).locale(locale))
}
let all: Set<Duration.UnitsFormatStyle.Unit> = [.weeks, .days, .hours, .minutes, .seconds]
let nw: Set<Duration.UnitsFormatStyle.Unit> = [.days, .hours, .minutes, .seconds]
for secs: Int64 in [0, 1, 5, 60, 65, 125, 3600, 3725, 86400, 90061, 400000, 700000] {
    print("units wide", secs, units(secs, nw, .wide, max: 2), "| abbr", units(secs, nw, .abbreviated, max: 2),
          "| narrow", units(secs, nw, .narrow, max: 2), "| condensed", units(secs, nw, .condensedAbbreviated, max: 2),
          "| show0", units(secs, nw, .wide, max: 2, zero: .show(length: 1)), "| de", units(secs, nw, .wide, max: 2, locale: de),
          "| deAbbr", units(secs, nw, .abbreviated, max: 2, locale: de))
}
print("units -125", units(-125, nw, .wide, max: 2))
print("units hm 3725", units(3725, [.hours, .minutes], .wide, max: 2, zero: .show(length: 1)))
print("units hm 3600", units(3600, [.hours, .minutes], .wide, max: 2, zero: .show(length: 1)))
print("units hm 86400", units(86400, [.days, .hours], .wide, max: 2, zero: .show(length: 1)))

// Components on Darwin
for style in [Date.ComponentsFormatStyle.Style.wide, .abbreviated, .narrow, .condensedAbbreviated, .spellOut] {
    for secs in [125.0, 3725, 90061, 400000, 2_678_400, 40_000_000] {
        let f = Date.ComponentsFormatStyle(style: style, locale: en, calendar: cal, fields: [.year, .month, .day, .hour, .minute, .second])
        print("components", style, secs, f.format(base..<at(secs)))
    }
}
let f2 = Date.ComponentsFormatStyle(style: .wide, locale: en, calendar: cal, fields: [.year, .month])
print("components y/m 40000000", f2.format(base..<at(40_000_000)))
print("components y/m 31622400", f2.format(base..<at(31_622_400)))
let f3 = Date.ComponentsFormatStyle(style: .wide, locale: de, calendar: cal, fields: [.year, .month])
print("components de y/m 40000000", f3.format(base..<at(40_000_000)))

// Relative
for presentation in [Date.RelativeFormatStyle.Presentation.named, .numeric] {
    let r = Date.RelativeFormatStyle(allowedFields: [.year, .month, .day, .hour, .minute], presentation: presentation, unitsStyle: .wide, locale: en, calendar: cal, capitalizationContext: .standalone)
    for t in [-400000.0, -90000, -3725, -125, -89.6, -30.6, -29.4, 0, 29.4, 29.6, 89.6, 125, 3725, 90000, 400000, 5_000_000] {
        print("relative \(presentation)", t, r.format(at(t)), "ref", base.timeIntervalSince(at(t)))
    }
}
let rr = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: en, calendar: cal)
print("relative plain now-30", rr.format(base.addingTimeInterval(-30)))
