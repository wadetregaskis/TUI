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
        parts.append("\(t).x=\(fmt(r.minX)) \(t).y=\(fmt(r.minY)) \(t).w=\(fmt(r.width)) \(t).h=\(fmt(r.height))")
    }
    let st = Frames.d["stack"] ?? .null
    print("\(label) || \(parts.joined(separator: " ")) outer.w=\(fmt(st.width)) outer.h=\(fmt(st.height))")
}

func tbox(_ s: String, _ tag: String) -> some View {
    Text(s).font(.system(size: 12, design: .monospaced)).background(Reader(tag: tag))
}

@MainActor func run() {
    print("== LazyVStack with Text rows (host 400 wide)")
    show("LazyVStack(leading){Text x guide 20; Text xxxxxx}",
         LazyVStack(alignment: .leading, spacing: 0) { tbox("x", "G").alignmentGuide(.leading) { _ in 20 }; tbox("xxxxxx", "S") }, ["G", "S"])
    show("LazyVStack(leading){Text x guide d.width; Text xxxxxx} (in-extent)",
         LazyVStack(alignment: .leading, spacing: 0) { tbox("x", "G").alignmentGuide(.leading) { d in d.width }; tbox("xxxxxx", "S") }, ["G", "S"])
    show("LazyVStack(leading){ForEach 0..<2 {box w=1 guide 5}; box w=6}",
         LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<1) { _ in box(1, 1, "G").alignmentGuide(.leading) { _ in 5 } }; box(6, 1, "S") }, ["G", "S"])
    print("== LazyHStack (host 200 tall)")
    show("LazyHStack(top){G h=1 guide 5; S h=6}",
         LazyHStack(alignment: .top, spacing: 0) { box(1, 1, "G").alignmentGuide(.top) { _ in 5 }; box(1, 6, "S") }, ["G", "S"])
    print("== propagation of the inner stack's OWN alignment guide")
    show("VStack(leading){VStack(leading){G w=6 guide=2; S w=6}; C w=6}",
         VStack(alignment: .leading, spacing: 0) {
             VStack(alignment: .leading, spacing: 0) { box(6, 1, "G").alignmentGuide(.leading) { _ in 2 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("VStack(leading){VStack(leading){G w=1 guide=5}; C w=6} (single child)",
         VStack(alignment: .leading, spacing: 0) {
             VStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 } }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "V", "C"])
    show("VStack(leading){VStack(center){G w=1 leading guide=5; S w=6}; C w=6} (other guide)",
         VStack(alignment: .leading, spacing: 0) {
             VStack(alignment: .center, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("VStack(trailing){VStack(leading){G w=1 trailing guide=0; S w=6}; C w=6} (other guide)",
         VStack(alignment: .trailing, spacing: 0) {
             VStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.trailing) { _ in 0 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("HStack(top){HStack(top){G h=1 guide=5; S h=6}; C h=6}",
         HStack(alignment: .top, spacing: 0) {
             HStack(alignment: .top, spacing: 0) { box(1, 1, "G").alignmentGuide(.top) { _ in 5 }; box(1, 6, "S") }.background(Reader(tag: "V"))
             box(1, 6, "C")
         }, ["G", "S", "V", "C"])
    show("HStack(top){HStack(center){G h=1 top guide=5; S h=6}; C h=6} (other guide)",
         HStack(alignment: .top, spacing: 0) {
             HStack(alignment: .center, spacing: 0) { box(1, 1, "G").alignmentGuide(.top) { _ in 5 }; box(1, 6, "S") }.background(Reader(tag: "V"))
             box(1, 6, "C")
         }, ["G", "S", "V", "C"])
    show("VStack(leading){ZStack(leading){G w=1 guide=5; S w=6}; C w=6}",
         VStack(alignment: .leading, spacing: 0) {
             ZStack(alignment: .leading) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("VStack(leading){ZStack(center){G w=1 leading guide=5; S w=6}; C w=6} (other guide)",
         VStack(alignment: .leading, spacing: 0) {
             ZStack(alignment: .center) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
    show("VStack(leading){HStack{G w=1 leading guide=5; S w=6}; C w=6}",
         VStack(alignment: .leading, spacing: 0) {
             HStack(spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }.background(Reader(tag: "V"))
             box(6, 1, "C")
         }, ["G", "S", "V", "C"])
}

MainActor.assumeIsolated { run() }
