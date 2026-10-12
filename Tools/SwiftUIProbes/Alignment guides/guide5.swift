import SwiftUI
import AppKit

// GUIDE: is an explicit alignment guide's value used as given, or clamped to
// the view's own size? Offscreen NSHostingView, after ../Dynamic properties/dp.swift.
// Children are fixed-size Color.clear frames so a point stands in for a cell.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 400, height: 200)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Frames { static var d: [String: CGRect] = [:] }

/// Records the frame of the view it is the background of, in the stack's space.
struct Reader: View {
    let tag: String
    var body: some View {
        GeometryReader { p in
            let r = p.frame(in: .named("s"))
            let _ = MainActor.assumeIsolated { Frames.d[tag] = r }
            Color.clear
        }
    }
}
struct StackReader: View {
    var body: some View {
        GeometryReader { p in
            let r = p.frame(in: .global)
            let _ = MainActor.assumeIsolated { Frames.d["stack"] = r }
            Color.clear
        }
    }
}

func box(_ w: CGFloat, _ h: CGFloat, _ tag: String) -> some View {
    Color.clear.frame(width: w, height: h).background(Reader(tag: tag))
}

func fmt(_ v: CGFloat) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}


@MainActor func show<V: View>(_ label: String, _ v: V, _ tags: [String]) {
    Frames.d = [:]
    _ = host(v.coordinateSpace(name: "s").background(StackReader())); spin()
    var parts: [String] = []
    for t in tags {
        let r = Frames.d[t] ?? .null
        parts.append("\(t).x=\(fmt(r.minX)) \(t).y=\(fmt(r.minY)) \(t).w=\(fmt(r.width))")
    }
    let st = Frames.d["stack"] ?? .null
    print("\(label) || \(parts.joined(separator: " ")) outer.w=\(fmt(st.width)) outer.h=\(fmt(st.height))")
}

@MainActor func inner(_ al: HorizontalAlignment, _ g: CGFloat) -> some View {
    VStack(alignment: al, spacing: 0) { box(1, 1, "G").alignmentGuide(al) { _ in g }; box(6, 1, "S") }.background(Reader(tag: "V"))
}

@MainActor func run() {
    print("== single child .background on a 20-wide base")
    for (al, an) in [(Alignment.trailing, "trailing"), (.leading, "leading")] {
        for g: CGFloat in [0, 5, -5] {
            show(".background(alignment: .\(an)) C w=6 guide=\(fmt(g))",
                 box(20, 1, "B").background(alignment: al) { box(6, 1, "C").alignmentGuide(al.horizontal) { _ in g } }, ["B", "C"])
        }
    }
    print("== single child .frame(height: 20) vertical")
    for g: CGFloat in [5, -5] {
        show(".frame(height: 20, alignment: .top) C h=6 guide=\(fmt(g))",
             box(1, 6, "C").alignmentGuide(.top) { _ in g }.frame(height: 20, alignment: .top), ["C"])
    }
}

MainActor.assumeIsolated { run() }
