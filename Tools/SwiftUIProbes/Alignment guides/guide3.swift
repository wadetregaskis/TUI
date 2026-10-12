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
    print("== propagation: inner VStack(leading){G w=1 guide=5; S w=6}")
    show("VStack(leading){inner; C w=6}", VStack(alignment: .leading, spacing: 0) { inner(.leading, 5); box(6, 1, "C") }, ["G", "S", "V", "C"])
    show("ZStack(leading){inner; C w=6}", ZStack(alignment: .leading) { inner(.leading, 5); box(6, 1, "C") }, ["G", "S", "V", "C"])
    show("inner.frame(width: 20, alignment: .leading)", inner(.leading, 5).frame(width: 20, alignment: .leading), ["G", "S", "V"])
    show("inner.frame(width: 20, alignment: .center)", inner(.leading, 5).frame(width: 20, alignment: .center), ["G", "S", "V"])
    show("C w=6 guide 5 .padding(0).frame(width: 20, alignment: .leading)",
         box(6, 1, "C").alignmentGuide(.leading) { _ in 5 }.padding(0).frame(width: 20, alignment: .leading), ["C"])
    show("inner.overlay base 20 leading", box(20, 1, "B").overlay(alignment: .leading) { inner(.leading, 5) }, ["B", "G", "S", "V"])
    print("== propagation: inner VStack(trailing){G w=1 guide=0; S w=6}")
    show("VStack(trailing){inner; C w=6}", VStack(alignment: .trailing, spacing: 0) { inner(.trailing, 0); box(6, 1, "C") }, ["G", "S", "V", "C"])
    show("inner.frame(width: 20, alignment: .trailing)", inner(.trailing, 0).frame(width: 20, alignment: .trailing), ["G", "S", "V"])
    print("== LazyVStack without fixedSize (host 400 wide)")
    show("LazyVStack(leading){G w=1 guide=5; S w=6}",
         LazyVStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }, ["G", "S"])
    show("LazyVStack(trailing){G w=3 guide=0; S w=6}",
         LazyVStack(alignment: .trailing, spacing: 0) { box(3, 1, "G").alignmentGuide(.trailing) { _ in 0 }; box(6, 1, "S") }, ["G", "S"])
    show("LazyVStack(center){G w=6 guide=0; S w=6}",
         LazyVStack(alignment: .center, spacing: 0) { box(6, 1, "G").alignmentGuide(HorizontalAlignment.center) { _ in 0 }; box(6, 1, "S") }, ["G", "S"])
    show("ScrollView{LazyVStack(leading){G w=1 guide=5; S w=6}}",
         ScrollView { LazyVStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") } }, ["G", "S"])
    show("ScrollView{LazyVStack(trailing){G w=3 guide=0; S w=6}}",
         ScrollView { LazyVStack(alignment: .trailing, spacing: 0) { box(3, 1, "G").alignmentGuide(.trailing) { _ in 0 }; box(6, 1, "S") } }, ["G", "S"])
    show("VStack(leading){G w=1 guide=5; S w=6}.frame(maxWidth: .infinity)",
         VStack(alignment: .leading, spacing: 0) { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 }; box(6, 1, "S") }.frame(maxWidth: .infinity), ["G", "S"])
}

MainActor.assumeIsolated { run() }
