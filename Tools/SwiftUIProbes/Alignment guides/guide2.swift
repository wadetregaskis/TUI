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


// GUIDE item 4 (2026-10-11): the same question for ZStack, LazyVStack, the
// single-child .frame/.overlay placement, a stack inside a frame (guide
// propagation), and a stack whose region is set by a flexible child.

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

@MainActor func run() {
    print("== ZStack")
    for g: CGFloat in [5, 25, -10] {
        show("ZStack(leading) G w=1 guide=\(fmt(g)) | S w=6",
             ZStack(alignment: .leading) { box(1, 1, "G").alignmentGuide(.leading) { _ in g }; box(6, 1, "S") }, ["G", "S"])
    }
    for g: CGFloat in [0, 10] {
        show("ZStack(trailing) G w=3 guide=\(fmt(g)) | S w=6",
             ZStack(alignment: .trailing) { box(3, 1, "G").alignmentGuide(.trailing) { _ in g }; box(6, 1, "S") }, ["G", "S"])
    }
    show("ZStack(top) G h=1 guide=5 | S h=6",
         ZStack(alignment: .top) { box(1, 1, "G").alignmentGuide(.top) { _ in 5 }; box(1, 6, "S") }, ["G", "S"])
    print("== LazyVStack")
    for g: CGFloat in [5, -10] {
        show("LazyVStack(leading) G w=1 guide=\(fmt(g)) | S w=6",
             LazyVStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in g }; box(6, 1, "S") }.fixedSize(), ["G", "S"])
    }
    show("LazyVStack(trailing) G w=3 guide=0 | S w=6",
         LazyVStack(alignment: .trailing, spacing: 0) { box(3, 1, "G").alignmentGuide(.trailing) { _ in 0 }; box(6, 1, "S") }.fixedSize(), ["G", "S"])
    print("== single child .frame(width: 20)")
    for (al, an) in [(Alignment.leading, "leading"), (.trailing, "trailing"), (.center, "center")] {
        for g: CGFloat in [0, 5, 25, -5] {
            show(".frame(width: 20, alignment: .\(an)) C w=6 guide=\(fmt(g))",
                 box(6, 1, "C").alignmentGuide(al.horizontal) { _ in g }.frame(width: 20, alignment: al).background(Reader(tag: "F")), ["C", "F"])
        }
    }
    print("== single child .overlay on a 20-wide base")
    for g: CGFloat in [5, -5, 25] {
        show(".overlay(alignment: .leading) C w=6 guide=\(fmt(g))",
             box(20, 1, "B").overlay(alignment: .leading) { box(6, 1, "C").alignmentGuide(.leading) { _ in g } }, ["B", "C"])
    }
    print("== a stack inside a fixed frame (its guide propagates)")
    show("VStack(trailing){G w=3 guide=0; S w=6}.frame(width: 20, alignment: .trailing)",
         VStack(alignment: .trailing, spacing: 0) { box(3, 1, "G").alignmentGuide(.trailing) { _ in 0 }; box(6, 1, "S") }
             .background(Reader(tag: "V")).frame(width: 20, alignment: .trailing), ["G", "S", "V"])
    show("VStack(leading){G w=1 guide=5; S w=6}.frame(width: 20, alignment: .leading)",
         VStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }
             .background(Reader(tag: "V")).frame(width: 20, alignment: .leading), ["G", "S", "V"])
    show("VStack(leading){VStack(leading){A w=5 guide=0; B w=5 guide=-100}; C w=6}",
         VStack(alignment: .leading, spacing: 0) {
             VStack(alignment: .leading, spacing: 0) {
                 box(5, 1, "A").alignmentGuide(.leading) { _ in 0 }
                 box(5, 1, "B").alignmentGuide(.leading) { _ in -100 }
             }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["A", "B", "C", "V"])
    print("== a region set by a flexible child (host is 400 wide)")
    show("VStack(trailing){G w=3 guide=0; S w=6; F maxWidth .infinity}",
         VStack(alignment: .trailing, spacing: 0) {
             box(3, 1, "G").alignmentGuide(.trailing) { _ in 0 }
             box(6, 1, "S")
             Color.clear.frame(maxWidth: .infinity, maxHeight: 1).background(Reader(tag: "F"))
         }, ["G", "S", "F"])
    show("VStack(leading){G w=1 guide=5; S w=6; F maxWidth .infinity}",
         VStack(alignment: .leading, spacing: 0) {
             box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }
             box(6, 1, "S")
             Color.clear.frame(maxWidth: .infinity, maxHeight: 1).background(Reader(tag: "F"))
         }, ["G", "S", "F"])
    show("VStack(center){G w=6 guide=0; S w=6; F maxWidth .infinity}",
         VStack(alignment: .center, spacing: 0) {
             box(6, 1, "G").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
             box(6, 1, "S")
             Color.clear.frame(maxWidth: .infinity, maxHeight: 1).background(Reader(tag: "F"))
         }, ["G", "S", "F"])
}

MainActor.assumeIsolated { run() }
