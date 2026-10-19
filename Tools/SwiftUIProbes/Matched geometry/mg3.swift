import SwiftUI
import AppKit

// MATCHED GEOMETRY under a 4 s linear animation, sampled every 0.5 s: a view
// inserted as another of its id is removed (if/else, A1; two separate ifs,
// A2, its content's laid-out size logged at every change); a follower whose
// id changes (A3); a source its layout moves (A4); a plain insertion (A5);
// and a follower inserted beside a standing source (A6). mg1's harness.

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

@MainActor final class Sizes { static var d: [String: CGSize] = [:] }
struct SizeReader: View {
    let tag: String
    var body: some View {
        GeometryReader { p in
            let s = p.size
            let _ = MainActor.assumeIsolated { Sizes.d[tag] = s }
            Color.clear
        }
    }
}

/// Every coloured layer, at its presentation frame in the hosting view.
@MainActor func sample(_ h: NSView) -> String {
    guard let root = h.layer else { return "no layer" }
    var found: [String] = []
    func walk(_ layer: CALayer) {
        let shown = layer.presentation() ?? layer
        if let colour = shown.backgroundColor, let rgb = NSColor(cgColor: colour)?.usingColorSpace(.sRGB), shown.opacity > 0.001 {
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
            found.append("\(name)@(\(Int(f.minX.rounded())),\(Int(f.minY.rounded())) \(Int(f.width.rounded()))x\(Int(f.height.rounded())))" + (shown.opacity < 0.999 ? String(format: " a%.2f", shown.opacity) : ""))
        }
        for sub in layer.sublayers ?? [] { walk(sub) }
    }
    walk(root)
    return found.joined(separator: "  ")
}

@Observable final class Model { var flag = false; var sel = 0 }
@MainActor final class SizeLog { static var lines: [String] = [] }
struct LoggingReader: View {
    let tag: String
    var body: some View {
        GeometryReader { p in
            let s = p.size
            let _ = MainActor.assumeIsolated {
                let line = "\(tag)=\(Int(s.width))x\(Int(s.height))"
                if SizeLog.lines.last != line { SizeLog.lines.append(line) }
            }
            Color.clear
        }
    }
}

struct Host<Content: View>: View {
    @Namespace var ns
    let model: Model
    let content: (Namespace.ID, Model) -> Content
    var body: some View {
        content(ns, model).frame(width: 400, height: 300, alignment: .topLeading)
    }
}

@MainActor func animate<C: View>(_ title: String, change: @escaping (Model) -> Void, duration: Double = 4, @ViewBuilder _ c: @escaping (Namespace.ID, Model) -> C) {
    let model = Model()
    SizeLog.lines = []
    let h = host(Host(model: model, content: c))
    spin()
    print("\(title)")
    print("  before: \(sample(h))")
    SizeLog.lines = []
    let start = Date()
    withAnimation(.linear(duration: duration)) { change(model) }
    var t = 0.0
    while t <= duration + 0.5 {
        let target = start.addingTimeInterval(t)
        RunLoop.main.run(until: target)
        print(String(format: "  t=%.1f: ", t) + sample(h))
        t += 0.5
    }
    if !SizeLog.lines.isEmpty { print("  sizes laid out: " + SizeLog.lines.joined(separator: " ")) }
    closeAll()
}

@main
struct MG3 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // A1: hero, if/else. Small RED at (10,10) 40x20; big BLUE at (200,150) 100x60.
        animate("A1 hero if/else", change: { $0.flag = true }) { ns, m in
            ZStack(alignment: .topLeading) {
                if !m.flag {
                    Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "h", in: ns)
                        .padding(.leading, 10).padding(.top, 10)
                } else {
                    Color.blue.background(LoggingReader(tag: "blue")).frame(width: 100, height: 60).matchedGeometryEffect(id: "h", in: ns)
                        .padding(.leading, 200).padding(.top, 150)
                }
            }
        }
        // A2: hero, two separate ifs in two different stacks.
        animate("A2 hero two ifs", change: { $0.flag = true }) { ns, m in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.green.frame(width: 10, height: 10)
                    if !m.flag {
                        Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "h", in: ns)
                    }
                }
                Color.clear.frame(width: 1, height: 100)
                HStack(spacing: 0) {
                    Color.clear.frame(width: 200, height: 10)
                    if m.flag {
                        Color.blue.background(LoggingReader(tag: "blue")).matchedGeometryEffect(id: "h", in: ns).frame(width: 100, height: 60)
                    }
                }
            }
        }
        // A3: a follower whose id changes: sources RED (40x20), ORANGE (60x30), PURPLE (20x40).
        animate("A3 follower id change 0 -> 2", change: { $0.sel = 2 }) { ns, m in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 30) {
                    Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: 0, in: ns)
                    Color.orange.frame(width: 60, height: 30).matchedGeometryEffect(id: 1, in: ns)
                    Color.purple.frame(width: 20, height: 40).matchedGeometryEffect(id: 2, in: ns)
                }
                .padding(20)
                Color.blue.opacity(0.5).background(LoggingReader(tag: "blue")).matchedGeometryEffect(id: m.sel, in: ns, isSource: false)
                    .frame(width: 10, height: 10)
            }
        }
        // A4: the source moves (its padding changes) under the animation.
        animate("A4 source moves", change: { $0.flag = true }) { ns, m in
            ZStack(alignment: .topLeading) {
                Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "a", in: ns)
                    .padding(.leading, m.flag ? 200 : 0)
                Color.blue.opacity(0.5).matchedGeometryEffect(id: "a", in: ns, isSource: false)
                    .frame(width: 10, height: 10).padding(.top, 100)
            }
        }
        // A5: a matched view inserted with no partner leaving.
        animate("A5 plain insertion", change: { $0.flag = true }) { ns, m in
            VStack(alignment: .leading, spacing: 0) {
                Color.green.frame(width: 10, height: 10)
                if m.flag {
                    Color.blue.frame(width: 100, height: 60).matchedGeometryEffect(id: "h", in: ns)
                }
            }
        }
        // A6: hero if/else where the inserted view is a follower (isSource: false) and
        // a source stays elsewhere.
        animate("A6 follower appears beside a standing source", change: { $0.flag = true }) { ns, m in
            ZStack(alignment: .topLeading) {
                Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "a", in: ns).padding(.leading, 200)
                if m.flag {
                    Color.blue.opacity(0.5).matchedGeometryEffect(id: "a", in: ns, isSource: false)
                        .frame(width: 10, height: 10).padding(.top, 100)
                }
            }
        }
        exit(0)
    }
}
