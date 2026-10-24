import SwiftUI
import AppKit

// TRANSITIONS, round 4 (lane VISUALS, decisions A34): what SwiftUI's
// blurReplace draws besides the blur, sampled every 0.25 s under a 2 s linear
// animation with tr1's harness: how far it scales, from which anchor, and
// whether it fades.
//  T16 .blurReplace (.downUp), inserted and removed;
//  T17 .blurReplace(.upUp), inserted and removed.

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
    _ title: String, change: @escaping (Model) -> Void, animation: Animation? = .linear(duration: 2),
    duration: Double = 2, setUp: (Model) -> Void = { _ in }, @ViewBuilder _ c: @escaping (Model) -> C
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
        print(String(format: "  t=%.2f: ", t) + sample(h))
        t += 0.25
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

@main
struct TR4 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        for (name, config) in [("downUp", BlurReplaceTransition.Configuration.downUp), ("upUp", .upUp)] {
            animate("blurReplace(.\(name)), inserted", change: { $0.flag = true }) { m in
                VStack(alignment: .leading, spacing: 0) {
                    Color.green.frame(width: 10, height: 10)
                    if m.flag { Color.red.frame(width: 200, height: 100).transition(.blurReplace(config)) }
                }
            }
            animate("blurReplace(.\(name)), removed", change: { $0.flag = false }, setUp: { $0.flag = true }) { m in
                VStack(alignment: .leading, spacing: 0) {
                    Color.green.frame(width: 10, height: 10)
                    if m.flag { Color.red.frame(width: 200, height: 100).transition(.blurReplace(config)) }
                }
            }
        }
        NSApp.terminate(nil)
    }
}
