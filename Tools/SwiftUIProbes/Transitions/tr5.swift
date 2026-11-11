import SwiftUI
import AppKit

// TRANSITIONS, round 5 (owner ruling ROW-REMOVAL (b), 2026-11-11): a change
// that interrupts a transition, sampled every 0.2 s under 2 s linear
// animations with tr1's harness. The second change comes 0.6 s (30%) into the
// first.
//  T18 .move(edge: .trailing), inserted, then removed mid-insertion;
//  T19 .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)), the same;
//  T20 .push(from: .trailing), the same;
//  T21 .opacity, removed, then inserted again mid-removal;
//  T22 .move(edge: .trailing), the same;
//  T23 T19's asymmetric move, the same;
//  T24 .push(from: .trailing), the same.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize = CGSize(width: 400, height: 300)) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func closeAll() {
    for w in keep { w.contentView = nil; w.close() }
    keep = []
    spin(0.1)
}

/// Every coloured layer, at its presentation frame in the hosting view.
@MainActor func sample(_ h: NSView) -> String {
    guard let root = h.layer else { return "no layer" }
    var found: [String] = []
    func walk(_ layer: CALayer, inherited: Float) {
        let shown = layer.presentation() ?? layer
        let alpha = inherited * shown.opacity
        if let colour = shown.backgroundColor, let rgb = NSColor(cgColor: colour)?.usingColorSpace(.sRGB), alpha > 0.001 {
            let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
            let name: String
            if r > 0.9 && g < 0.3 && b < 0.3 { name = "RED" }
            else if r < 0.3 && g > 0.6 && b < 0.4 { name = "GREEN" }
            else if r < 0.2 && g < 0.6 && b > 0.9 { name = "BLUE" }
            else if r > 0.9 && g > 0.7 && b < 0.2 { name = "YELLOW" }
            else if r > 0.9 && g > 0.4 && g < 0.7 && b < 0.2 { name = "ORANGE" }
            else if r > 0.5 && g < 0.4 && b > 0.5 { name = "PURPLE" }
            else { name = String(format: "rgb(%.2f,%.2f,%.2f)", r, g, b) }
            let f = shown.convert(shown.bounds, to: root.presentation() ?? root)
            found.append("\(name)@(\(Int(f.minX.rounded())),\(Int(f.minY.rounded())) \(Int(f.width.rounded()))x\(Int(f.height.rounded())))" + (alpha < 0.999 ? String(format: " a%.2f", alpha) : ""))
        }
        for sub in layer.sublayers ?? [] { walk(sub, inherited: alpha) }
    }
    walk(root, inherited: 1)
    return found.joined(separator: "  ")
}

@Observable final class Model { var flag = false; var sel = 0; var rows = [0, 2] }

struct Host<Content: View>: View {
    let model: Model
    let content: (Model) -> Content
    var body: some View {
        content(model).frame(width: 400, height: 300, alignment: .topLeading)
    }
}

@MainActor func interrupt<C: View>(
    _ title: String, first: @escaping (Model) -> Void, second: @escaping (Model) -> Void,
    after: Double = 0.6, setUp: (Model) -> Void = { _ in }, @ViewBuilder _ c: @escaping (Model) -> C
) {
    let model = Model()
    setUp(model)
    let h = host(Host(model: model, content: c))
    spin()
    print("\(title)")
    print("  before: \(sample(h))")
    let start = Date()
    withAnimation(.linear(duration: 2)) { first(model) }
    var t = 0.0
    var interrupted = false
    while t <= after + 2.6 {
        if !interrupted && t >= after - 0.001 {
            RunLoop.main.run(until: start.addingTimeInterval(after))
            withAnimation(.linear(duration: 2)) { second(model) }
            interrupted = true
            print(String(format: "  -- second change at %.2f", after))
        }
        RunLoop.main.run(until: start.addingTimeInterval(t))
        print(String(format: "  t=%.2f: ", t) + sample(h))
        t += 0.2
    }
    closeAll()
}

@main
struct TR5 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let cases: [(String, AnyTransition)] = [
            ("move(edge: .trailing)", .move(edge: .trailing)),
            ("asymmetric(move .trailing, move .leading)",
             .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))),
            ("push(from: .trailing)", .push(from: .trailing)),
        ]
        for (name, transition) in cases {
            interrupt("\(name), inserted then removed at 30%",
                      first: { $0.flag = true }, second: { $0.flag = false }) { m in
                VStack(alignment: .leading, spacing: 0) {
                    Color.green.frame(width: 10, height: 10)
                    if m.flag { Color.red.frame(width: 200, height: 100).transition(transition) }
                }
            }
        }
        for (name, transition) in [("opacity", AnyTransition.opacity)] + cases {
            interrupt("\(name), removed then inserted again at 30%",
                      first: { $0.flag = false }, second: { $0.flag = true }, setUp: { $0.flag = true }) { m in
                VStack(alignment: .leading, spacing: 0) {
                    Color.green.frame(width: 10, height: 10)
                    if m.flag { Color.red.frame(width: 200, height: 100).transition(transition) }
                }
            }
        }
        NSApp.terminate(nil)
    }
}
