import SwiftUI
import AppKit

// ANIMATION MODIFIER ORDER, the cases p10 left open (the semantic audit's
// item 4): a delay inside an AUTOREVERSING repeat, a delay outside a repeat,
// a delay after a speed inside a repeat, and a repeat of a repeat. The value
// SwiftUI hands an Animatable modifier, sampled every 0.05 s from the change,
// to two decimals; offscreen NSHostingView, as p10.

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

/// The value at every 0.05 s from the change: the last sample at or before it.
func series(_ title: String, until end: Double) {
    let v = Samples.values
    var out: [String] = []
    var t = 0.0
    while t <= end + 1e-9 {
        let at = v.last { $0.0 <= t + 0.008 }?.1 ?? 0
        out.append(String(format: "%.2f", at))
        t += 0.05
    }
    print("\(title):")
    print("  " + out.joined(separator: " "))
}

@MainActor func run(_ tag: Int, _ title: String, _ animation: Animation, for seconds: Double) {
    let model = Model()
    Samples.current = tag
    host(Probe(tag: tag, model: model)); spin(0.3)
    Samples.values = []; Samples.start = Date()
    withAnimation(animation) { model.on = true }
    spin(seconds)
    series(title, until: seconds - 0.1)
    keep.forEach { $0.close() }; keep = []
}

@main
struct Main {
    @MainActor static func main() {
        let linear = Animation.linear(duration: 0.4)
        run(1, "delay(0.3).repeatForever(autoreverses: true)", linear.delay(0.3).repeatForever(autoreverses: true), for: 2.4)
        run(2, "delay(0.3).repeatCount(2, autoreverses: true)", linear.delay(0.3).repeatCount(2, autoreverses: true), for: 2.0)
        run(3, "repeatCount(2, autoreverses: false).delay(0.3)", linear.repeatCount(2, autoreverses: false).delay(0.3), for: 1.6)
        run(4, "speed(2).delay(0.3).repeatCount(2, autoreverses: false)", linear.speed(2).delay(0.3).repeatCount(2, autoreverses: false), for: 1.6)
        run(5, "delay(0.2).repeatCount(2, autoreverses: false).delay(0.3)", linear.delay(0.2).repeatCount(2, autoreverses: false).delay(0.3), for: 2.0)
        run(6, "repeatCount(2, autoreverses: false).repeatCount(2, autoreverses: false)", linear.repeatCount(2, autoreverses: false).repeatCount(2, autoreverses: false), for: 2.2)
        run(7, "delay(0.3).speed(2).repeatCount(2, autoreverses: false)", linear.delay(0.3).speed(2).repeatCount(2, autoreverses: false), for: 1.2)
        run(8, "repeatCount(2, autoreverses: false).speed(2)", linear.repeatCount(2, autoreverses: false).speed(2), for: 1.0)
    }
}
