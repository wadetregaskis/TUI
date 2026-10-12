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

@MainActor func vcase(_ alignment: HorizontalAlignment, _ aname: String, guided gw: CGFloat, sibling sw: CGFloat, guide g: CGFloat) {
    Frames.d = [:]
    let v = VStack(alignment: alignment, spacing: 0) {
        box(gw, 1, "G").alignmentGuide(alignment) { _ in g }
        box(sw, 1, "S")
    }
    .coordinateSpace(name: "s")
    .background(StackReader())
    _ = host(v); spin()
    let G = Frames.d["G"] ?? .null, S = Frames.d["S"] ?? .null, st = Frames.d["stack"] ?? .null
    print("VStack(\(aname)) G w=\(fmt(gw)) guide=\(fmt(g)) | S w=\(fmt(sw)) || G.x=\(fmt(G.minX)) S.x=\(fmt(S.minX)) stack.w=\(fmt(st.width))")
}

@MainActor func hcase(_ alignment: VerticalAlignment, _ aname: String, guided gh: CGFloat, sibling sh: CGFloat, guide g: CGFloat) {
    Frames.d = [:]
    let v = HStack(alignment: alignment, spacing: 0) {
        box(1, gh, "G").alignmentGuide(alignment) { _ in g }
        box(1, sh, "S")
    }
    .coordinateSpace(name: "s")
    .background(StackReader())
    _ = host(v); spin()
    let G = Frames.d["G"] ?? .null, S = Frames.d["S"] ?? .null, st = Frames.d["stack"] ?? .null
    print("HStack(\(aname)) G h=\(fmt(gh)) guide=\(fmt(g)) | S h=\(fmt(sh)) || G.y=\(fmt(G.minY)) S.y=\(fmt(S.minY)) stack.h=\(fmt(st.height))")
}

/// The original observation's shape with Text: a one-character Text with a
/// monospaced font beside a six-character one.
@MainActor func textCase(_ g: CGFloat) {
    Frames.d = [:]
    let v = VStack(alignment: .leading, spacing: 0) {
        Text("x").font(.system(size: 12, design: .monospaced)).background(Reader(tag: "G"))
            .alignmentGuide(.leading) { _ in g }
        Text("xxxxxx").font(.system(size: 12, design: .monospaced)).background(Reader(tag: "S"))
    }
    .coordinateSpace(name: "s")
    .background(StackReader())
    _ = host(v); spin()
    let G = Frames.d["G"] ?? .null, S = Frames.d["S"] ?? .null, st = Frames.d["stack"] ?? .null
    print("Text VStack(leading) G=\"x\" w=\(fmt(G.width)) guide=\(fmt(g)) | S=\"xxxxxx\" w=\(fmt(S.width)) || G.x=\(fmt(G.minX)) S.x=\(fmt(S.minX)) stack.w=\(fmt(st.width))")
}

@MainActor func run() {
    let guides: [CGFloat] = [0, 1, 2, 5, 10, 15, 25, -1, -3, -10]
    print("== leading")
    for gw: CGFloat in [1, 6, 10] {
        for sw: CGFloat in [6, 10] {
            for g in guides { vcase(.leading, "leading", guided: gw, sibling: sw, guide: g) }
        }
    }
    print("== trailing (sibling's own trailing guide = its width)")
    for gw: CGFloat in [1, 6] {
        for g in guides { vcase(.trailing, "trailing", guided: gw, sibling: 6, guide: g) }
    }
    print("== center (sibling's own center guide = width/2)")
    for gw: CGFloat in [1, 6] {
        for g in guides { vcase(.center, "center", guided: gw, sibling: 6, guide: g) }
    }
    print("== HStack top")
    for gh: CGFloat in [1, 6] {
        for g in guides { hcase(.top, "top", guided: gh, sibling: 6, guide: g) }
    }
    print("== HStack bottom")
    for g in guides { hcase(.bottom, "bottom", guided: 1, sibling: 6, guide: g) }
    print("== control: in-extent guides only")
    vcase(.trailing, "trailing", guided: 3, sibling: 6, guide: 0)
    vcase(.trailing, "trailing", guided: 3, sibling: 6, guide: 1)
    vcase(.center, "center", guided: 6, sibling: 6, guide: -6)
    vcase(.center, "center", guided: 6, sibling: 6, guide: 0)
    hcase(.bottom, "bottom", guided: 3, sibling: 6, guide: 0)
    print("== Text, monospaced 12pt")
    for g: CGFloat in [0, 5, 20] { textCase(g) }
}

MainActor.assumeIsolated { run() }
