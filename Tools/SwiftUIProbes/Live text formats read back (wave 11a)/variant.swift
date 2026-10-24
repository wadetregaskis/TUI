import SwiftUI
import AppKit
import Vision

// Does `.textVariant(.sizeDependent)` change what any text draws when it is
// short of room? Each case drawn at several widths, with and without it.
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

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        if #available(macOS 15, *) {
            for w in [400.0, 160, 100, 60] {
                print("w\(w) dateTime   ", drawn(Text(.currentDate, format: .dateTime).textVariant(.sizeDependent).frame(width: w)),
                      "| fixed", drawn(Text(.currentDate, format: .dateTime).frame(width: w)))
                let wide = Date.FormatStyle().weekday(.wide).month(.wide).day().year()
                print("w\(w) wide date  ", drawn(Text(fixed, format: wide).textVariant(.sizeDependent).frame(width: w)),
                      "| fixed", drawn(Text(fixed, format: wide).frame(width: w)))
                print("w\(w) ref max3   ", drawn(Text(.currentDate, format: .reference(to: fixed, maxFieldCount: 3)).textVariant(.sizeDependent).frame(width: w).lineLimit(1)),
                      "| fixed", drawn(Text(.currentDate, format: .reference(to: fixed, maxFieldCount: 3)).frame(width: w).lineLimit(1)))
                print("w\(w) offset 1line", drawn(Text(.currentDate, format: .offset(to: fixed)).textVariant(.sizeDependent).frame(width: w).lineLimit(1)),
                      "| fixed", drawn(Text(.currentDate, format: .offset(to: fixed)).frame(width: w).lineLimit(1)))
                print("w\(w) timer 1line", drawn(Text(.currentDate, format: .timer(countingUpIn: fixed..<Date.distantFuture)).textVariant(.sizeDependent).frame(width: w).lineLimit(1)),
                      "| fixed", drawn(Text(.currentDate, format: .timer(countingUpIn: fixed..<Date.distantFuture)).frame(width: w).lineLimit(1)))
            }
        }
    }
}
