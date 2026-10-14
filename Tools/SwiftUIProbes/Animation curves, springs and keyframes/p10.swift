import SwiftUI
import AppKit

// ANIMATION DELAY COMPOSITION (the semantic audit's item 4): does a delay
// repeat with `repeatForever`, and does a delay written after `speed` scale
// with it? An Animatable modifier records the value SwiftUI hands it each
// frame, with the time since the change; offscreen NSHostingView.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) {
    let size = CGSize(width: 100, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

enum Samples {
    nonisolated(unsafe) static var start = Date()
    nonisolated(unsafe) static var values: [(Double, Double)] = []
    nonisolated(unsafe) static var current = 0
}

struct Recorder: ViewModifier, Animatable {
    let tag: Int
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    func body(content: Content) -> some View {
        if tag == Samples.current { Samples.values.append((Date().timeIntervalSince(Samples.start), value)) }
        return content.opacity(value)
    }
}

@Observable final class Model { var on = false }

struct Probe: View {
    let tag: Int
    let model: Model
    var body: some View {
        Color.red.frame(width: 10, height: 10).modifier(Recorder(tag: tag, value: model.on ? 1 : 0))
    }
}

/// When the value first leaves 0, and how often it falls back to the start (a
/// new pass beginning), to a tenth of a second, so reruns compare with diff.
func summarise(_ title: String) {
    let v = Samples.values
    let firstMove = v.first { $0.1 > 0.02 }?.0
    var restarts: [Double] = []
    for i in 1..<max(1, v.count) where v[i].1 < v[i - 1].1 - 0.5 { restarts.append(v[i].0) }
    let tenth = { (d: Double) in String(format: "%.1f", d) }
    let period = restarts.count >= 2 ? (restarts.last! - restarts.first!) / Double(restarts.count - 1) : nil
    // The delays in question are 0.3 s and 0.6 s: name the nearer, since the
    // first frame drawn moving falls anywhere in the frame after the delay.
    let delay = firstMove.map { abs($0 - 0.3) < abs($0 - 0.6) ? "about 0.3 s" : "about 0.6 s" } ?? "-"
    print("\(title): first move after \(delay); \(period.map { "a pass every \(tenth($0)) s" } ?? "no repeat")")
}

@main
struct Main {
    @MainActor static func main() {
        // (1) linear 0.4 s, delay 0.3 s, repeat forever without reversing.
        let a = Model()
        Samples.current = 1
        host(Probe(tag: 1, model: a)); spin(0.3)
        Samples.values = []; Samples.start = Date()
        withAnimation(.linear(duration: 0.4).delay(0.3).repeatForever(autoreverses: false)) { a.on = true }
        spin(2.4)
        summarise("delay(0.3).repeatForever, linear 0.4")
        keep.forEach { $0.close() }; keep = []

        // (2) speed(2) then delay(0.6): is the delay 0.6 s or 0.3 s?
        let b = Model()
        Samples.current = 2
        host(Probe(tag: 2, model: b)); spin(0.3)
        Samples.values = []; Samples.start = Date()
        withAnimation(.linear(duration: 0.4).speed(2).delay(0.6)) { b.on = true }
        spin(1.5)
        summarise("speed(2).delay(0.6), linear 0.4")
        keep.forEach { $0.close() }; keep = []

        // (3) delay(0.6) then speed(2): the order both frameworks agree on.
        let c = Model()
        Samples.current = 3
        host(Probe(tag: 3, model: c)); spin(0.3)
        Samples.values = []; Samples.start = Date()
        withAnimation(.linear(duration: 0.4).delay(0.6).speed(2)) { c.on = true }
        spin(1.5)
        summarise("delay(0.6).speed(2), linear 0.4")
    }
}
