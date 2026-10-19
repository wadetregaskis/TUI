import SwiftUI
import AppKit

// MATCHED GEOMETRY, a follower whose content takes the size it is offered
// (a Color inside a 10x10 frame), for each property set and each pair of
// anchors; then a fixed-size content and one larger than its source.
// The harness is mg1's: an offscreen NSHostingView, what is DRAWN read from
// the layer tree (presentation frames of the coloured layers), and what the
// content is laid out at from a GeometryReader inside it.

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

struct Case<Content: View>: View {
    @Namespace var ns
    let content: (Namespace.ID) -> Content
    var body: some View {
        content(ns).frame(width: 400, height: 300, alignment: .topLeading)
    }
}

@MainActor func run<C: View>(_ title: String, @ViewBuilder _ c: @escaping (Namespace.ID) -> C) {
    Sizes.d = [:]
    let h = host(Case(content: c))
    spin()
    let sizes = Sizes.d.keys.sorted().map { "\($0)=\(Int(Sizes.d[$0]!.width))x\(Int(Sizes.d[$0]!.height))" }.joined(separator: " ")
    print("\(title): \(sample(h))" + (sizes.isEmpty ? "" : "  [laid out: \(sizes)]"))
    closeAll()
}

/// Source: RED 40x20 at (100, 0). Follower: BLUE, its own 10x10 frame,
/// first in a VStack with GREEN below it (whose y says what height the
/// follower takes in the layout). The follower's content reads its size.
@MainActor func follower(_ title: String, properties: MatchedGeometryProperties, anchor: UnitPoint = .center, flexible: Bool = false, sourceID: String = "a", followerID: String = "a") {
    run(title) { ns in
        ZStack(alignment: .topLeading) {
            Color.red.frame(width: 40, height: 20)
                .matchedGeometryEffect(id: sourceID, in: ns)
                .offset(x: 100, y: 0)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if flexible {
                        Color.blue.background(SizeReader(tag: "blue"))
                            .matchedGeometryEffect(id: followerID, in: ns, properties: properties, anchor: anchor, isSource: false)
                            .frame(width: 10, height: 10)
                    } else {
                        Color.blue.background(SizeReader(tag: "blue")).frame(width: 10, height: 10)
                            .matchedGeometryEffect(id: followerID, in: ns, properties: properties, anchor: anchor, isSource: false)
                    }
                }
                Color.green.frame(width: 30, height: 5)
            }
            .offset(x: 0, y: 50)
        }
    }
}

@main
struct MG2 {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // Source RED 40x20 at (100,0) by padding; follower BLUE flexible inside
        // a 10x10 frame at (0,50); GREEN after it.
        func flex(_ title: String, _ p: MatchedGeometryProperties, follower fa: UnitPoint = .center, source sa: UnitPoint = .center) {
            run(title) { ns in
                VStack(alignment: .leading, spacing: 0) {
                    Color.red.frame(width: 40, height: 20)
                        .matchedGeometryEffect(id: "a", in: ns, anchor: sa)
                        .padding(.leading, 100)
                    Color.clear.frame(width: 1, height: 30)
                    Color.blue.background(SizeReader(tag: "blue"))
                        .matchedGeometryEffect(id: "a", in: ns, properties: p, anchor: fa, isSource: false)
                        .frame(width: 10, height: 10)
                    Color.green.frame(width: 30, height: 5)
                }
            }
        }
        flex("F1 .frame", .frame)
        flex("F2 .position", .position)
        flex("F3 .size", .size)
        flex("F4 .size follower topLeading", .size, follower: .topLeading)
        flex("F5 .size follower bottomTrailing", .size, follower: .bottomTrailing)
        flex("F6 .frame follower topLeading", .frame, follower: .topLeading)
        flex("F7 .frame source topLeading", .frame, source: .topLeading)
        flex("F8 .frame both topLeading", .frame, follower: .topLeading, source: .topLeading)
        flex("F9 .position source topLeading", .position, source: .topLeading)
        flex("F10 .position both bottomTrailing", .position, follower: .bottomTrailing, source: .bottomTrailing)
        // A follower with a fixed-size content smaller than the source, both anchors topLeading.
        run("F11 fixed content, both topLeading") { ns in
            VStack(alignment: .leading, spacing: 0) {
                Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "a", in: ns, anchor: .topLeading).padding(.leading, 100)
                Color.clear.frame(width: 1, height: 30)
                Color.blue.frame(width: 10, height: 10).matchedGeometryEffect(id: "a", in: ns, anchor: .topLeading, isSource: false)
                Color.green.frame(width: 30, height: 5)
            }
        }
        // Text inside the follower: is it laid out at the source's width?
        run("F12 follower bigger than source (fixed 60x40 content)") { ns in
            VStack(alignment: .leading, spacing: 0) {
                Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "a", in: ns).padding(.leading, 100)
                Color.clear.frame(width: 1, height: 30)
                Color.blue.frame(width: 60, height: 40).matchedGeometryEffect(id: "a", in: ns, isSource: false)
                Color.green.frame(width: 30, height: 5)
            }
        }
        // The source itself with isSource: true and properties: .position only.
        run("F13 source has properties .position") { ns in
            VStack(alignment: .leading, spacing: 0) {
                Color.red.frame(width: 40, height: 20).matchedGeometryEffect(id: "a", in: ns, properties: .position).padding(.leading, 100)
                Color.clear.frame(width: 1, height: 30)
                Color.blue.background(SizeReader(tag: "blue")).matchedGeometryEffect(id: "a", in: ns, isSource: false).frame(width: 10, height: 10)
                Color.green.frame(width: 30, height: 5)
            }
        }
        exit(0)
    }
}
