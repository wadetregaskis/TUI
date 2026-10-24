import SwiftUI
import AppKit
import Vision

// Reads what SwiftUI draws for a live Text by rendering it and running OCR on
// the picture (the accessibility tree is empty without an assistive client).
// Every target date is taken from the clock just before its own render, so
// the offsets below are what the text was asked to show, give or take the
// render's own few milliseconds; the fractional offsets keep each case half a
// second from any boundary.
@MainActor func drawn<V: View>(_ v: V, locale: Locale = Locale(identifier: "en_US")) -> String {
    let renderer = ImageRenderer(content: v.padding(8).background(Color.white).environment(\.locale, locale)
        .environment(\.timeZone, TimeZone(identifier: "UTC")!))
    renderer.scale = 4
    guard let cg = renderer.cgImage else { return "<no image>" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cg)
    try? handler.perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: " / ")
}

/// Whether two views draw the same pixels.
@MainActor func same<A: View, B: View>(_ a: A, _ b: B) -> Bool {
    func png<V: View>(_ v: V) -> Data? {
        let r = ImageRenderer(content: v.padding(8).background(Color.white).environment(\.locale, Locale(identifier: "en_US")))
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
    return png(a) == png(b)
}

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        func at(_ s: Double) -> Date { Date().addingTimeInterval(s) }
        let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        print("time", drawn(Text(fixed, style: .time)))
        print("date", drawn(Text(fixed, style: .date)))
        print("time de", drawn(Text(fixed, style: .time), locale: Locale(identifier: "de_DE")))
        print("date de", drawn(Text(fixed, style: .date), locale: Locale(identifier: "de_DE")))
        // past (negative) and future (positive) offsets
        let mags = [0.3, 0.7, 1.5, 9.5, 59.5, 60.5, 119.5, 3599.5, 3600.5, 3659.5, 3779.5, 86399.5, 86400.5, 90061.5, 172800.5, 2_678_400.5, 31_622_400.5, 40_000_000.5]
        for m in mags {
            print("relative past", m, drawn(Text(at(-m), style: .relative)), "| future", drawn(Text(at(m), style: .relative)))
        }
        for m in mags {
            print("offset past", m, drawn(Text(at(-m), style: .offset)), "| future", drawn(Text(at(m), style: .offset)))
        }
        for m in [0.3, 0.7, 1.5, 9.5, 59.5, 60.5, 3599.5, 3600.5, 86400.5, 400000.5] {
            print("timer past", m, drawn(Text(at(-m), style: .timer)), "| future", drawn(Text(at(m), style: .timer)))
        }
        print("relative de", drawn(Text(at(-3725.5), style: .relative), locale: Locale(identifier: "de_DE")))
        print("offset de", drawn(Text(at(-3725.5), style: .offset), locale: Locale(identifier: "de_DE")))
        // The minus sign: hyphen-minus or U+2212?
        let far = at(40_000_000)
        print("offset minus is hyphen", same(Text(far, style: .offset), Text(verbatim: "-1 year")),
              "is U+2212", same(Text(far, style: .offset), Text(verbatim: "\u{2212}1 year")))
        print("offset plus", same(Text(at(-40_000_000), style: .offset), Text(verbatim: "+1 year")))
        // Timer interval
        let a = at(-30.5), b = a.addingTimeInterval(3725)
        print("tI down", drawn(Text(timerInterval: a...b)))
        print("tI up", drawn(Text(timerInterval: a...b, countsDown: false)))
        print("tI noHours", drawn(Text(timerInterval: a...a.addingTimeInterval(7200), showsHours: false)))
        print("tI before start down", drawn(Text(timerInterval: at(100.5)...at(200.5))))
        print("tI before start up", drawn(Text(timerInterval: at(100.5)...at(200.5), countsDown: false)))
        print("tI after end down", drawn(Text(timerInterval: at(-200.5)...at(-100.5))))
        print("tI after end up", drawn(Text(timerInterval: at(-200.5)...at(-100.5), countsDown: false)))
        let s = at(-60.5)
        print("tI paused past down", drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(20))))
        print("tI paused past up", drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(20), countsDown: false)))
        print("tI paused future", drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(200))))
        print("tI paused before start", drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(-20))))
        print("tI big", drawn(Text(timerInterval: at(-0.5)...at(400000))))
        // Interpolations
        print("interp relative", drawn(Text("Ends \(at(-125.5), style: .relative) ago")))
        print("interp timer", drawn(Text("Left: \(timerInterval: at(-0.5)...at(90))")))
        print("interp time", drawn(Text("At \(fixed, style: .time)")))
        // Time data sources
        if #available(macOS 15, *) {
            print("src ref", drawn(Text(.currentDate, format: .reference(to: at(-125.5)))))
            print("src offset", drawn(Text(.currentDate, format: .offset(to: at(-125.5)))))
            print("src timer", drawn(Text(.currentDate, format: .timer(countingDownIn: at(-0.5)..<at(90)))))
            print("src stopwatch", drawn(Text(.currentDate, format: .stopwatch(startingAt: at(-65.5)))))
            print("src dateTime", drawn(Text(.currentDate, format: Date.FormatStyle(date: .omitted, time: .standard))))
            print("src durationOffset", drawn(Text(.durationOffset(to: at(-125.5)), format: .time(pattern: .minuteSecond))))
            print("src durationOffset fut", drawn(Text(.durationOffset(to: at(125.5)), format: .time(pattern: .minuteSecond))))
            print("src dateRange start", drawn(Text(.dateRange(startingAt: at(-125.5)), format: .components(style: .wide))))
            print("src dateRange end", drawn(Text(.dateRange(endingAt: at(125.5)), format: .components(style: .wide))))
            print("src dateRange start future", drawn(Text(.dateRange(startingAt: at(125.5)), format: .components(style: .wide))))
            // Size variants
            for w in [300.0, 140, 100, 70, 50, 30] {
                print("variant offset w\(w)", drawn(Text(.currentDate, format: .offset(to: at(-3725.5))).textVariant(.sizeDependent).frame(width: w)),
                      "| fixed", drawn(Text(.currentDate, format: .offset(to: at(-3725.5))).frame(width: w)))
                print("variant ref w\(w)", drawn(Text(.currentDate, format: .reference(to: at(-5_000_000))).textVariant(.sizeDependent).frame(width: w)))
                print("variant timer w\(w)", drawn(Text(.currentDate, format: .timer(countingDownIn: at(-0.5)..<at(3725))).textVariant(.sizeDependent).frame(width: w)))
                print("variant style relative w\(w)", drawn(Text(at(-3725.5), style: .relative).textVariant(.sizeDependent).frame(width: w)))
                print("variant style date w\(w)", drawn(Text(fixed, style: .date).textVariant(.sizeDependent).frame(width: w)))
            }
        }
        // accessibilityName
        for (n, c) in [("red", Color.red), ("blue", .blue), ("custom", Color(red: 0.2, green: 0.4, blue: 0.8)), ("gray", Color(white: 0.5)), ("dark", Color(red: 0.1, green: 0.3, blue: 0.1)), ("primary", .primary), ("accent", .accentColor)] {
            print("axname", n, drawn(Text("C: \(accessibilityName: c)")))
        }
    }
}
