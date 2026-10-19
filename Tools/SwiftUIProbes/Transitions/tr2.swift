import SwiftUI
import AppKit

// TRANSITIONS, round 2 (lane TRANSITIONS2): how a transition's own animations
// compose, sampled every 0.5 s with tr1's harness (itself mg3's):
//  T9  an outer .animation over asymmetric halves, the insertion with its own;
//  T10 two .animation calls;
//  T11 .animation(nil) then .animation(8 s), and the reverse;
//  T12 combined parts, each with an animation of its own, and with nil;
//  T13 asymmetric with .animation(nil) on the removal.

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

@MainActor func animate<C: View>(
    _ title: String, change: @escaping (Model) -> Void, animation: Animation? = .linear(duration: 4),
    duration: Double = 4, setUp: (Model) -> Void = { _ in }, @ViewBuilder _ c: @escaping (Model) -> C
) {
    let model = Model()
    setUp(model)
    let h = host(Host(model: model, content: c))
    spin()
    print("\(title)")
    print("  before: \(sample(h))")
    let start = Date()
    if let animation {
        withAnimation(animation) { change(model) }
    } else {
        change(model)
    }
    var t = 0.0
    while t <= duration + 0.5 {
        let target = start.addingTimeInterval(t)
        RunLoop.main.run(until: target)
        print(String(format: "  t=%.1f: ", t) + sample(h))
        t += 0.5
    }
    closeAll()
}

func colour(_ id: Int) -> Color {
    switch id {
    case 0: .red
    case 1: .orange
    case 2: .blue
    default: .purple
    }
}

struct Collapse: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.frame(height: phase.isIdentity ? nil : 0, alignment: .top).clipped()
    }
}

struct WholeBody: View {
    let flag: Bool
    var body: some View {
        if flag {
            Color.blue.frame(width: 100, height: 60)
        } else {
            Color.red.frame(width: 40, height: 20)
        }
    }
}

@main
struct TR2 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // T9: an outer .animation over asymmetric halves, one with its own.
        let outer = AnyTransition.asymmetric(
            insertion: .opacity.animation(.linear(duration: 2)), removal: .opacity
        ).animation(.linear(duration: 8))
        animate("T9 (asym(ins 2 s, rem none)).animation(8 s) inserted under 4 s", change: { $0.flag = true }, duration: 8) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(outer) }
            }
        }
        animate("T9b same removed under 4 s", change: { $0.flag = false }, duration: 8, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(outer) }
            }
        }
        // T10: two .animation calls.
        let twice = AnyTransition.opacity.animation(.linear(duration: 2)).animation(.linear(duration: 8))
        animate("T10 .opacity.animation(2 s).animation(8 s) inserted under 4 s", change: { $0.flag = true }, duration: 8) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(twice) }
            }
        }
        // T11: .animation(nil) then .animation(8 s), and the reverse.
        let nilThen = AnyTransition.opacity.animation(nil).animation(.linear(duration: 8))
        animate("T11 .opacity.animation(nil).animation(8 s) inserted under 4 s", change: { $0.flag = true }, duration: 8) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(nilThen) }
            }
        }
        let thenNil = AnyTransition.opacity.animation(.linear(duration: 8)).animation(nil)
        animate("T11b .opacity.animation(8 s).animation(nil) inserted under 4 s", change: { $0.flag = true }, duration: 8) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(thenNil) }
            }
        }
        // T12: combined, each half its own animation.
        let both = AnyTransition.opacity.animation(.linear(duration: 2)).combined(with: AnyTransition.opacity.animation(.linear(duration: 8)))
        animate("T12 opacity(2 s).combined(opacity(8 s)) inserted under 4 s", change: { $0.flag = true }, duration: 8) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(both) }
            }
        }
        let partly = AnyTransition.opacity.animation(nil).combined(with: .offset(x: 100))
        animate("T12b opacity(nil).combined(offset 100) inserted under 4 s", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(partly) }
            }
        }
        // T13: asymmetric with a nil removal.
        let nilRemoval = AnyTransition.asymmetric(insertion: .opacity, removal: .opacity.animation(nil))
        animate("T13 asym(ins opacity, rem opacity.animation(nil)) removed under 4 s", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(nilRemoval) }
            }
        }
        animate("T13b same inserted under 4 s", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(nilRemoval) }
            }
        }
        NSApp.terminate(nil)
    }
}
