import SwiftUI
import AppKit
import Vision

// Text(timerInterval:pauseTime:countsDown:) with a pause: what a paused timer
// shows, counting down and up, with the pause before, inside and after the
// interval and before and after now.
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
        // The interval started 60.5 s ago and lasts 600 s.
        for pause in [-100.0, -20, 0, 20, 50, 59, 60, 61, 100, 599, 700] {
            for down in [true, false] {
                let s = Date().addingTimeInterval(-60.5)
                let text = drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(pause), countsDown: down))
                print("pause at start+\(pause) countsDown \(down):", text)
            }
        }
        // And a timer whose interval has not started.
        for down in [true, false] {
            let s = Date().addingTimeInterval(100.5)
            print("not started, pause at start+20, countsDown \(down):",
                  drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(20), countsDown: down)))
        }
        // Over: ended 100 s ago.
        for down in [true, false] {
            let s = Date().addingTimeInterval(-700.5)
            print("ended, pause at start+20, countsDown \(down):",
                  drawn(Text(timerInterval: s...s.addingTimeInterval(600), pauseTime: s.addingTimeInterval(20), countsDown: down)))
        }
        // The documented example: 12 minutes from now, paused at now + 10 min.
        let now = Date()
        print("doc example:", drawn(Text(timerInterval: now...Date(timeInterval: 12 * 60, since: now), pauseTime: now + (10 * 60))))
        // The SystemFormatStyle.Timer counterpart, deterministic.
        if #available(macOS 15, *) {
            let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let f = SystemFormatStyle.Timer(countingDownIn: base..<base.addingTimeInterval(600)).locale(Locale(identifier: "en_US"))
            print("format at start+20:", String(f.format(base.addingTimeInterval(20)).characters))
        }
    }
}
