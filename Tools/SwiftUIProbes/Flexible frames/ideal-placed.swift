import SwiftUI
import AppKit

// ideal-placed (lane LAYOUT review, 2026-10-19): a frame with an ideal width and no maximum round a 5-wide box,
// under .fixedSize(), as each container places it — which pass SwiftUI's unspecified width on to it (the frame is
// its ideal, 10) and which offer it a width (its content's, 5). Output in ideal-placed.out.
// Offscreen NSHostingView, the harness of layout1.swift beside the alignment-guide probes. 1 pt stands in for 1 cell.

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


func fr(_ w: CGFloat = 5, align: Alignment = .trailing) -> some View {
    box(w, 1, "T").frame(idealWidth: 10, alignment: align).background(Reader(tag: "F"))
}

@MainActor func run() {
    print("== F3: a frame(idealWidth: 10) round a 5-wide box, under .fixedSize(), placed by a container")
    show("fr.fixedSize()", fr().fixedSize(), ["T", "F"])
    show("VStack(lead){fr; box25}.fixedSize()", VStack(alignment: .leading, spacing: 0) { fr(); box(25, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("VStack{fr}.fixedSize()", VStack(spacing: 0) { fr() }.fixedSize(), ["T", "F"])
    show("VStack{fr; box3}.fixedSize()", VStack(spacing: 0) { fr(); box(3, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("ZStack(lead){fr; box25}.fixedSize()", ZStack(alignment: .leading) { fr(); box(25, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("ZStack{fr}.fixedSize()", ZStack { fr() }.fixedSize(), ["T", "F"])
    show("HStack{fr; box3}.fixedSize()", HStack(spacing: 0) { fr(); box(3, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("VStackLayout(lead){fr; box25}.fixedSize()", VStackLayout(alignment: .leading, spacing: 0) { fr(); box(25, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("HStackLayout{fr; box3}.fixedSize()", HStackLayout(spacing: 0) { fr(); box(3, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("ZStackLayout(lead){fr; box25}.fixedSize()", ZStackLayout(alignment: .leading) { fr(); box(25, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("HStack{VStack(lead){fr; box7}; box3}.fixedSize()", HStack(spacing: 0) { VStack(alignment: .leading, spacing: 0) { fr(); box(7, 1, "S") }; box(3, 1, "U") }.fixedSize(), ["T", "F", "S", "U"])
    show("VStack(lead){HStack{fr; box3}; box25}.fixedSize()", VStack(alignment: .leading, spacing: 0) { HStack(spacing: 0) { fr(); box(3, 1, "U") }; box(25, 1, "S") }.fixedSize(), ["T", "F", "U", "S"])
    show("fr.padding(1).fixedSize()", fr().padding(1).fixedSize(), ["T", "F"])
    show("fr.border.fixedSize()", fr().border(Color.red).fixedSize(), ["T", "F"])
    show("fr.background{box30}.fixedSize()", fr().background(box(30, 1, "B")).fixedSize(), ["T", "F", "B"])
    show("box25.overlay(alignment: .leading){fr}.fixedSize()", box(25, 1, "S").overlay(alignment: .leading) { fr() }.fixedSize(), ["T", "F", "S"])
    show("Grid(lead){GridRow{fr}; GridRow{box25}}.fixedSize()", Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) { GridRow { fr() }; GridRow { box(25, 1, "S") } }.fixedSize(), ["T", "F", "S"])
    show("VStack(lead){fr; box25} in 400 (no fixedSize)", VStack(alignment: .leading, spacing: 0) { fr(); box(25, 1, "S") }, ["T", "F", "S"])
    show("ScrollView(.horizontal){VStack(lead){fr; box25}}", ScrollView(.horizontal) { VStack(alignment: .leading, spacing: 0) { fr(); box(25, 1, "S") } }.frame(width: 40, height: 3), ["T", "F", "S"])
}

@main struct Probe { static func main() { setlinebuf(stdout); MainActor.assumeIsolated { run() } } }
