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

extension HorizontalAlignment { enum Mark: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] } }; static let mark = HorizontalAlignment(Mark.self) }

@MainActor func run() {
    print("== two children, both explicit (inner VStack(center), outer VStack(leading) with C w=6)")
    show("inner{G w=1 leading 5; S w=6 leading 1}",
         VStack(alignment: .leading, spacing: 0) {
             VStack(alignment: .center, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S").alignmentGuide(.leading) { _ in 1 } }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    print("== custom alignment .mark, two children, one explicit")
    show("outer VStack(.mark){inner VStack(center){G w=1 mark 5; S w=6}; C w=6}",
         VStack(alignment: .mark, spacing: 0) {
             VStack(alignment: .center, spacing: 0) { box(1, 1, "G").alignmentGuide(.mark) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("outer VStack(.mark){inner HStack{G w=1 mark 5; S w=6}; C w=6}",
         VStack(alignment: .mark, spacing: 0) {
             HStack(spacing: 0) { box(1, 1, "G").alignmentGuide(.mark) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    print("== built-in .leading, inner HStack, two children, guide on the second")
    show("outer VStack(leading){inner HStack{S w=6; G w=1 leading 0}; C w=6}",
         VStack(alignment: .leading, spacing: 0) {
             HStack(spacing: 0) { box(6, 1, "S"); box(1, 1, "G").alignmentGuide(.leading) { _ in 0 } }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
}

MainActor.assumeIsolated { run() }
