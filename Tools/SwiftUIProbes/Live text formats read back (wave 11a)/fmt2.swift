import SwiftUI
import Foundation

// Deterministic measurements of SwiftUI's SystemFormatStyle family on macOS 15:
// strings, rounding, discrete boundaries. Every case formats against a fixed
// base date, in en_US, Gregorian, in UTC.
let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
func at(_ s: Double) -> Date { base.addingTimeInterval(s) }
let en = Locale(identifier: "en_US")
var utcCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = en
    return c
}()
func s(_ a: AttributedString) -> String { String(a.characters).debugDescription }
func off(_ d: Date?) -> String { d.map { String($0.timeIntervalSince(base)) } ?? "nil" }

print("== Timer")
do {
    let down = SystemFormatStyle.Timer(countingDownIn: at(0)..<at(3725)).locale(en)
    for t in [-10.0, 0, 0.4, 0.6, 1, 9.5, 3124.9, 3125.1, 3724.2, 3724.9, 3725, 9000] {
        print("down 3725 t=\(t)", s(down.format(at(t))), "after", off(down.discreteInput(after: at(t))),
              "before", off(down.discreteInput(before: at(t))))
    }
    let up = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(3725)).locale(en)
    for t in [-10.0, 0, 0.4, 0.6, 1, 9.5, 59.9, 60, 3599.9, 3600, 3724.9, 3725, 9000] {
        print("up 3725 t=\(t)", s(up.format(at(t))), "after", off(up.discreteInput(after: at(t))),
              "before", off(up.discreteInput(before: at(t))))
    }
    let noH = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(100000), showsHours: false).locale(en)
    for t in [5.0, 3725, 99999] { print("up noHours t=\(t)", s(noH.format(at(t)))) }
    for n in [1, 2, 3, 4] {
        let f = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(100000), maxFieldCount: n).locale(en)
        for t in [5.0, 65, 3725] { print("up maxField\(n) t=\(t)", s(f.format(at(t)))) }
    }
    for p in [Duration.seconds(60), .seconds(10), .milliseconds(100), .milliseconds(10), .milliseconds(1)] {
        let f = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(100000), maxPrecision: p).locale(en)
        for t in [5.678, 65.678, 3725.678] {
            print("up prec\(p) t=\(t)", s(f.format(at(t))), "after", off(f.discreteInput(after: at(t))))
        }
        let g = SystemFormatStyle.Timer(countingDownIn: at(0)..<at(100000), maxPrecision: p).locale(en)
        print("down prec\(p) t=5.678", s(g.format(at(5.678))), "after", off(g.discreteInput(after: at(5.678))))
    }
    let big = SystemFormatStyle.Timer(countingUpIn: at(0)..<at(1_000_000)).locale(en)
    print("up big t=400000", s(big.format(at(400000))))
    print("de down", s(down.locale(Locale(identifier: "de_DE")).format(at(0))))
    print("input after", off(down.input(after: at(10))), "before", off(down.input(before: at(10))))
}

print("== Stopwatch")
do {
    let sw = SystemFormatStyle.Stopwatch(startingAt: base).locale(en)
    for t in [-5.0, 0, 0.004, 0.006, 1.234, 59.999, 65.5, 3599.99, 3600, 3725.25, 400000] {
        print("sw t=\(t)", s(sw.format(at(t))), "after", off(sw.discreteInput(after: at(t))),
              "before", off(sw.discreteInput(before: at(t))))
    }
    let noH = SystemFormatStyle.Stopwatch(startingAt: base, showsHours: false).locale(en)
    print("sw noHours t=3725.25", s(noH.format(at(3725.25))))
    for n in [1, 2, 3, 4] {
        let f = SystemFormatStyle.Stopwatch(startingAt: base, maxFieldCount: n).locale(en)
        for t in [5.25, 65.25, 3725.25] { print("sw maxField\(n) t=\(t)", s(f.format(at(t)))) }
    }
    for p in [Duration.seconds(60), .seconds(1), .milliseconds(100), .milliseconds(1)] {
        let f = SystemFormatStyle.Stopwatch(startingAt: base, maxPrecision: p).locale(en)
        for t in [5.678, 65.678, 3725.678] {
            print("sw prec\(p) t=\(t)", s(f.format(at(t))), "after", off(f.discreteInput(after: at(t))))
        }
    }
}

print("== DateOffset")
do {
    let o = SystemFormatStyle.DateOffset(to: base).locale(en).calendar(utcCal)
    for t in [-90000.0, -3725, -125, -59.6, -59.4, -30, -0.6, -0.4, 0, 0.4, 0.6, 1, 59.4, 59.6, 60, 119.6,
              125, 3599.6, 3600, 3725, 3779.6, 86399, 86400, 90000, 2_678_400, 40_000_000] {
        print("off t=\(t)", s(o.format(at(t))), "after", off(o.discreteInput(after: at(t))),
              "before", off(o.discreteInput(before: at(t))))
    }
    for sign in [NumberFormatStyleConfiguration.SignDisplayStrategy.automatic, .never, .always(), .always(includingZero: false)] {
        let f = SystemFormatStyle.DateOffset(to: base, sign: sign).locale(en).calendar(utcCal)
        for t in [-30.0, 0, 30] { print("off sign\(sign) t=\(t)", s(f.format(at(t)))) }
    }
    for n in [1, 3] {
        let f = SystemFormatStyle.DateOffset(to: base, maxFieldCount: n).locale(en).calendar(utcCal)
        for t in [3725.0, 90061] { print("off max\(n) t=\(t)", s(f.format(at(t)))) }
    }
    let ms = SystemFormatStyle.DateOffset(to: base, allowedFields: [.minute, .second]).locale(en).calendar(utcCal)
    for t in [5.0, 125, 3725, -125] { print("off m:s t=\(t)", s(ms.format(at(t))), "after", off(ms.discreteInput(after: at(t)))) }
    let hms = SystemFormatStyle.DateOffset(to: base, allowedFields: [.hour, .minute, .second]).locale(en).calendar(utcCal)
    for t in [5.0, 125, 3725, 90061] { print("off h:m:s t=\(t)", s(hms.format(at(t)))) }
    let hm = SystemFormatStyle.DateOffset(to: base, allowedFields: [.hour, .minute]).locale(en).calendar(utcCal)
    for t in [5.0, 125, 3725, 90061] { print("off h:m t=\(t)", s(hm.format(at(t)))) }
    let dw = SystemFormatStyle.DateOffset(to: base, allowedFields: [.week, .day]).locale(en).calendar(utcCal)
    for t in [5.0, 90061, 700000, 2_678_400] { print("off w:d t=\(t)", s(dw.format(at(t)))) }
    print("off de t=3725", s(o.locale(Locale(identifier: "de_DE")).format(at(3725))))
    print("off input after", off(o.input(after: at(10))), "before", off(o.input(before: at(10))))
}

print("== DateReference")
do {
    let r = SystemFormatStyle.DateReference(to: base).locale(en).calendar(utcCal)
    for t in [-40_000_000.0, -5_000_000, -400_000, -200_000, -90000, -86400, -3725, -3599, -125, -89.4, -30.6, -29.4, -0.6, 0, 0.4, 0.6, 29.4, 29.6, 30, 89.4, 89.6, 125, 3599, 3600, 5399.6, 86399, 86400, 90000, 172_800, 200_000, 400_000, 5_000_000, 40_000_000] {
        print("ref t=\(t)", s(r.format(at(t))), "after", off(r.discreteInput(after: at(t))),
              "before", off(r.discreteInput(before: at(t))))
    }
    let r3 = SystemFormatStyle.DateReference(to: base, maxFieldCount: 3).locale(en).calendar(utcCal)
    for t in [-5_000_000.0, 5_000_000, 40_000_000] { print("ref max3 t=\(t)", s(r3.format(at(t)))) }
    let r1 = SystemFormatStyle.DateReference(to: base, maxFieldCount: 1).locale(en).calendar(utcCal)
    for t in [-5_000_000.0, 5_000_000, 40_000_000] { print("ref max1 t=\(t)", s(r1.format(at(t)))) }
    let rh = SystemFormatStyle.DateReference(to: base, thresholdField: .hour).locale(en).calendar(utcCal)
    for t in [-90000.0, -3725, 3725, 90000] { print("ref thrHour t=\(t)", s(rh.format(at(t)))) }
    let rm = SystemFormatStyle.DateReference(to: base, thresholdField: .month).locale(en).calendar(utcCal)
    for t in [-90000.0, -400_000, 400_000, 5_000_000, 40_000_000] { print("ref thrMonth t=\(t)", s(rm.format(at(t)))) }
    let rs = SystemFormatStyle.DateReference(to: base, allowedFields: [.minute, .second], thresholdField: .minute).locale(en).calendar(utcCal)
    for t in [-125.0, -30, 30, 125, 3725, 90000] { print("ref m:s t=\(t)", s(rs.format(at(t))), "after", off(rs.discreteInput(after: at(t)))) }
    print("ref de t=125", s(r.locale(Locale(identifier: "de_DE")).format(at(125))))
    print("ref de t=-90000", s(r.locale(Locale(identifier: "de_DE")).format(at(-90000))))
    print("ref input after", off(r.input(after: at(10))), "before", off(r.input(before: at(10))))
}

print("== Codable")
do {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    print(String(data: try! e.encode(SystemFormatStyle.Stopwatch(startingAt: base)), encoding: .utf8)!)
    print(String(data: try! e.encode(SystemFormatStyle.DateOffset(to: base)), encoding: .utf8)!)
    print(String(data: try! e.encode(SystemFormatStyle.DateReference(to: base)), encoding: .utf8)!)
    print(String(data: try! e.encode(Text.DateStyle.relative), encoding: .utf8)!)
    print(String(data: try! e.encode(Text.DateStyle.timer), encoding: .utf8)!)
}
