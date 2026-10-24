// TEXTFMT (2026-10-24): what SwiftUI draws for a value interpolated into a Text's
// key — a number with no specifier, a substring, an attributed string, a date
// range and interval — read back by rendering through ImageRenderer and Vision
// (the accessibility tree is empty without an assistive client). Also
// Foundation's own interval formats, for comparison with the range's.
import SwiftUI
import AppKit
import Vision

@MainActor func drawn<V: View>(_ v: V, locale: String = "en_US") -> String {
    let renderer = ImageRenderer(content: v.padding(8).background(Color.white).environment(\.locale, Locale(identifier: locale)))
    renderer.scale = 4
    guard let cg = renderer.cgImage else { return "<no image>" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cg)
    try? handler.perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " / ")
}

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let r1 = base...base.addingTimeInterval(3600)
        let r2 = base...base.addingTimeInterval(86400 * 3)
        let r3 = base...base.addingTimeInterval(86400 * 400)
        print("range 1h", drawn(Text(r1)))
        print("range 3d", drawn(Text(r2)))
        print("range 400d", drawn(Text(r3)))
        print("interval 1h", drawn(Text(DateInterval(start: base, duration: 3600))))
        print("interval 3d", drawn(Text(DateInterval(start: base, duration: 86400 * 3))))
        print("interp range 1h", drawn(Text("a \(r1) b")))
        print("interp interval 3d", drawn(Text("a \(DateInterval(start: base, duration: 86400 * 3)) b")))
        print("int", drawn(Text("a \(1234567) b")))
        print("int8", drawn(Text("a \(Int8(-5)) b")))
        print("uint", drawn(Text("a \(UInt(1234567)) b")))
        print("double", drawn(Text("a \(3.5) b")))
        print("float", drawn(Text("a \(Float(3.25)) b")))
        print("double big", drawn(Text("a \(1234567.25) b")))
        print("int de", drawn(Text("a \(1234567) b"), locale: "de_DE"))
        print("double de", drawn(Text("a \(3.5) b"), locale: "de_DE"))
        print("substring", drawn(Text("a \("xyz".dropFirst()) b")))
        print("attributed", drawn(Text("a \(AttributedString("attr")) b")))
        let en = Locale(identifier: "en_US")
        var st = Date.IntervalFormatStyle(); st.locale = en
        print("IntervalFormatStyle en_US 1h", st.format(r1.lowerBound..<r1.upperBound))
        print("IntervalFormatStyle en_US 3d", st.format(r2.lowerBound..<r2.upperBound))
        let f = DateIntervalFormatter(); f.locale = en
        print("DateIntervalFormatter default en_US 1h", f.string(from: r1.lowerBound, to: r1.upperBound))
        f.dateStyle = .short; f.timeStyle = .short
        print("DIF short/short 1h", f.string(from: r1.lowerBound, to: r1.upperBound))
        print("DIF short/short 3d", f.string(from: r2.lowerBound, to: r2.upperBound))
        f.dateStyle = .medium; f.timeStyle = .short
        print("DIF medium/short 1h", f.string(from: r1.lowerBound, to: r1.upperBound))
        print("tz", TimeZone.current.identifier)
    }
}
