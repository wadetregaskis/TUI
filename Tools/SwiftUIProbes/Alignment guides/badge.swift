import SwiftUI
import AppKit

// badge (lane LAYOUT review, 2026-10-19): a custom guide set on a view passes .badge and .textCase, which change
// nothing of the view's geometry, as it passes no modifier at all. Output in badge.out.
// Offscreen NSHostingView, the harness of layout1.swift. 1 pt stands in for 1 cell.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, _ size: CGSize = CGSize(width: 400, height: 200)) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.sizingOptions = []
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

struct Reader: View {
    let tag: String
    var space: String = "s"
    var body: some View {
        GeometryReader { p in
            let r = p.frame(in: .named(space))
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
    if v.isNaN { return "nan" }
    if !v.isFinite { return v > 0 ? "inf" : "-inf" }
    if abs(v) >= 1e7 { return String(format: "%.3g", v) }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}

@MainActor func show<V: View>(_ label: String, _ v: V, _ tags: [String], size: CGSize = CGSize(width: 400, height: 200)) {
    Frames.d = [:]
    _ = host(v.coordinateSpace(name: "s").background(StackReader()), size); spin()
    var parts: [String] = []
    for t in tags {
        let r = Frames.d[t] ?? .null
        parts.append("\(t).x=\(fmt(r.minX)) \(t).y=\(fmt(r.minY)) \(t).w=\(fmt(r.width)) \(t).h=\(fmt(r.height))")
    }
    let st = Frames.d["stack"] ?? .null
    print("\(label) || \(parts.joined(separator: " ")) outer.w=\(fmt(st.width)) outer.h=\(fmt(st.height))")
}


extension HorizontalAlignment {
    private enum Mark: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] } }
    static let mark = HorizontalAlignment(Mark.self)
}

@MainActor func run() {
    print("== F7: a custom guide through .badge in VStack(alignment: .mark){G.badge; C}")
    show("G(mark 3).badge(2)", VStack(alignment: .mark, spacing: 0) { box(4, 1, "G").alignmentGuide(.mark) { _ in 3 }.badge(2); box(1, 1, "C") }, ["G", "C"])
    show("G(mark 3).badge(\"x\")", VStack(alignment: .mark, spacing: 0) { box(4, 1, "G").alignmentGuide(.mark) { _ in 3 }.badge("x"); box(1, 1, "C") }, ["G", "C"])
    show("G(mark 3) (no badge)", VStack(alignment: .mark, spacing: 0) { box(4, 1, "G").alignmentGuide(.mark) { _ in 3 }; box(1, 1, "C") }, ["G", "C"])
    show("G(mark 3).textCase", VStack(alignment: .mark, spacing: 0) { box(4, 1, "G").alignmentGuide(.mark) { _ in 3 }.textCase(.uppercase); box(1, 1, "C") }, ["G", "C"])
}

@main struct Probe { static func main() { setlinebuf(stdout); MainActor.assumeIsolated { run() } } }
