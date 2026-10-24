import SwiftUI
import AppKit
import Vision

// Reads what SwiftUI draws for a Text by rendering it and running OCR on the
// picture: the accessibility tree is empty without an assistive client.
@MainActor func drawn<V: View>(_ v: V) -> String {
    let renderer = ImageRenderer(content: v.padding(8).background(Color.white).environment(\.locale, Locale(identifier: "en_US")))
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

@main struct P {
    @MainActor static func main() {
        _ = NSApplication.shared
        let now = Date()
        func at(_ s: Double) -> Date { now.addingTimeInterval(s) }
        print("time", drawn(Text(Date(timeIntervalSinceReferenceDate: 800_000_000), style: .time)))
        print("date", drawn(Text(Date(timeIntervalSinceReferenceDate: 800_000_000), style: .date)))
        for s in [-400000.0, -90000, -3725, -125, -30, -1, 0, 1, 30, 125, 3725, 90000, 400000, 40_000_000] {
            print("relative", s, drawn(Text(at(s), style: .relative)))
        }
        for s in [-400000.0, -90000, -3725, -125, -30, -1, 0, 1, 30, 125, 3725, 90000, 400000, 40_000_000] {
            print("offset", s, drawn(Text(at(s), style: .offset)))
        }
        for s in [-400000.0, -90000, -3725, -125, -30, -1, 0, 1, 30, 125, 3725, 90000, 400000] {
            print("timer", s, drawn(Text(at(s), style: .timer)))
        }
    }
}
