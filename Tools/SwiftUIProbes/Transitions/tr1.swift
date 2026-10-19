import SwiftUI
import AppKit

// TRANSITIONS (lane TRANSITIONS2): what SwiftUI does, sampled every 0.5 s
// under a linear animation, with mg3's harness (Tools/SwiftUIProbes/Matched
// geometry/mg3.swift):
//  T1 an if/else branch flip in a column, no .transition;
//  T2 a switch of three cases, no .transition;
//  T3 a ForEach row inserted and removed, no .transition;
//  T4 asymmetric halves with animations of their own;
//  T5 .opacity.animation(nil) under withAnimation;
//  T6 a transition's own animation with no withAnimation;
//  T7 a custom transition that collapses its height (B52);
//  T8 a view's whole body an if/else, no .transition.

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
struct TR1 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // T1: GREEN 10x10; RED 40x20 (true branch) / BLUE 100x60 (false); YELLOW 10x10.
        animate("T1 if/else flip in a VStack", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                if !m.flag {
                    Color.red.frame(width: 40, height: 20)
                } else {
                    Color.blue.frame(width: 100, height: 60)
                }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        animate("T1b if/else flip back", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                if !m.flag {
                    Color.red.frame(width: 40, height: 20)
                } else {
                    Color.blue.frame(width: 100, height: 60)
                }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        // T2: a switch, 0 -> 2.
        animate("T2 switch 0 -> 2 in a VStack", change: { $0.sel = 2 }) { m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                switch m.sel {
                case 0: Color.red.frame(width: 40, height: 20)
                case 1: Color.orange.frame(width: 60, height: 30)
                default: Color.purple.frame(width: 20, height: 40)
                }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        // T3: ForEach rows, ids [0, 2] -> [0, 1, 2] and back.
        animate("T3 ForEach row inserted", change: { $0.rows = [0, 1, 2] }) { m in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(m.rows, id: \.self) { id in colour(id).frame(width: CGFloat(40 + 20 * id), height: 20) }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        animate("T3b ForEach row removed", change: { $0.rows = [0, 2] }, setUp: { $0.rows = [0, 1, 2] }) { m in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(m.rows, id: \.self) { id in colour(id).frame(width: CGFloat(40 + 20 * id), height: 20) }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        // T4: asymmetric halves, insertion 2 s and removal 8 s, under a 4 s change.
        let halves = AnyTransition.asymmetric(
            insertion: .opacity.animation(.linear(duration: 2)), removal: .opacity.animation(.linear(duration: 8)))
        animate("T4 asymmetric insertion (2 s) under 4 s", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(halves) }
            }
        }
        animate("T4b asymmetric removal (8 s) under 4 s", change: { $0.flag = false }, duration: 8, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(halves) }
            }
        }
        // T4c: only the insertion has an animation of its own; the removal takes the change's.
        let insertionOnly = AnyTransition.asymmetric(
            insertion: .opacity.animation(.linear(duration: 2)), removal: .opacity)
        animate("T4c asymmetric, removal without its own, under 4 s", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(insertionOnly) }
            }
        }
        // T5: .animation(nil) under withAnimation.
        animate("T5 .opacity.animation(nil) inserted under 4 s", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(.opacity.animation(nil)) }
            }
        }
        animate("T5b .opacity.animation(nil) removed under 4 s", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(.opacity.animation(nil)) }
            }
        }
        // T5c: the Transition protocol's spelling.
        animate("T5c OpacityTransition().animation(nil) inserted under 4 s", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(OpacityTransition().animation(nil)) }
            }
        }
        // T6: a transition's own animation, the change unanimated.
        animate("T6 .opacity.animation(.linear(4)) inserted, no withAnimation", change: { $0.flag = true }, animation: nil) { m in
            VStack(alignment: .leading, spacing: 0) {
                if m.flag { Color.red.frame(width: 40, height: 20).transition(.opacity.animation(.linear(duration: 4))) }
            }
        }
        // T7: a custom transition that collapses its height, removed.
        animate("T7 collapsing transition removed", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                if m.flag { Color.red.frame(width: 40, height: 60).transition(Collapse()) }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        animate("T7b collapsing transition inserted", change: { $0.flag = true }) { m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                if m.flag { Color.red.frame(width: 40, height: 60).transition(Collapse()) }
                Color.yellow.frame(width: 10, height: 10)
            }
        }
        // T8: a view whose whole body is an if/else, alone in a frame.
        animate("T8 whole body if/else", change: { $0.flag = true }) { m in
            WholeBody(flag: m.flag)
        }
        NSApp.terminate(nil)
    }
}
