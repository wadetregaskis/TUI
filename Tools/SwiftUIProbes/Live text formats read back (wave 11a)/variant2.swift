import SwiftUI
import AppKit
import Vision

// The ladder of size variants each live text offers under
// `.textVariant(.sizeDependent)` on one line: every distinct reading as the
// width falls, widest first.
@MainActor func drawn<V: View>(_ v: V) -> String {
    let renderer = ImageRenderer(content: v.padding(8).background(Color.white).environment(\.locale, Locale(identifier: "en_US")))
    renderer.scale = 4
    guard let cg = renderer.cgImage else { return "<no image>" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cg).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " / ")
}

@available(macOS 15, *) @MainActor func ladder(_ name: String, _ make: () -> Text) {
    var seen: [String] = []
    var widths: [String] = []
    for w in stride(from: 260.0, through: 16, by: -6) {
        let s = drawn(make().textVariant(.sizeDependent).frame(width: w).lineLimit(1))
        if seen.last != s {
            seen.append(s)
            widths.append("\(Int(w))")
        }
    }
    print(name, "→", zip(widths, seen).map { "[\($0)] \($1)" }.joined(separator: "  "))
}

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        func at(_ s: Double) -> Date { Date().addingTimeInterval(s) }
        let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        if #available(macOS 15, *) {
            ladder("offset 3725") { Text(.currentDate, format: .offset(to: at(-3725.5))) }
            ladder("offset 125") { Text(.currentDate, format: .offset(to: at(-125.5))) }
            ladder("offset 40M") { Text(.currentDate, format: .offset(to: at(-40_000_000))) }
            ladder("offset -125") { Text(.currentDate, format: .offset(to: at(125.5))) }
            ladder("reference -125") { Text(.currentDate, format: .reference(to: at(-125.5))) }
            ladder("reference +3725") { Text(.currentDate, format: .reference(to: at(3725.5))) }
            ladder("reference yesterday") { Text(.currentDate, format: .reference(to: at(-90000))) }
            ladder("reference abs") { Text(.currentDate, format: .reference(to: fixed)) }
            ladder("reference abs max3") { Text(.currentDate, format: .reference(to: fixed, maxFieldCount: 3)) }
            ladder("reference abs year") { Text(.currentDate, format: .reference(to: at(-40_000_000))) }
            ladder("timer 3725 max2") { Text(.currentDate, format: .timer(countingUpIn: at(-3725.5)..<at(100000), maxFieldCount: 2)) }
            ladder("stopwatch") { Text(.currentDate, format: .stopwatch(startingAt: at(-3725.5))) }
            ladder("style relative") { Text(at(-3725.5), style: .relative) }
            ladder("style offset") { Text(at(-3725.5), style: .offset) }
            ladder("style date") { Text(fixed, style: .date) }
            ladder("style time") { Text(fixed, style: .time) }
            ladder("style timer") { Text(at(-3725.5), style: .timer) }
        }
    }
}
