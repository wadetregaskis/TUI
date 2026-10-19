import SwiftUI
import AppKit

// layout1 (lane LAYOUT, 2026-10-18): which guides leave which containers (decisions A-GUIDE-2) and how a
// guide passes single-child wrappers (SA-L11), case A to C; EmptyView under modifiers and a frame's ideal
// offered nothing (case D). Run with A, B, C or D; output in layout1.out.
// Offscreen NSHostingView, the harness of GUIDE2's g2d.swift (session notes). 1 pt stands in for 1 cell.

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


// A: built-in guides out of statically-one-view layouts, app views, branches; baselines out of rows and layouts.
// B: a guide through single-child wrappers (frame, border, offset, overlay, background, padding, fixedSize).

extension HorizontalAlignment {
    private enum Mark: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] } }
    static let mark = HorizontalAlignment(Mark.self)
}

struct SimpleColumn: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            s.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(sz))
            y += sz.height
        }
    }
}
struct SimpleRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(sz))
            x += sz.width
        }
    }
}

@MainActor func outer<I: View>(_ inner: I) -> some View {
    VStack(alignment: .leading, spacing: 0) { inner.background(Reader(tag: "V")); box(6, 1, "C") }
}
@MainActor func outerC<I: View>(_ inner: I) -> some View {
    VStack(alignment: .center, spacing: 0) { inner.background(Reader(tag: "V")); box(6, 1, "C") }
}
@MainActor func outerT<I: View>(_ inner: I) -> some View {
    VStack(alignment: .trailing, spacing: 0) { inner.background(Reader(tag: "V")); box(6, 1, "C") }
}
@MainActor func outerMark<I: View>(_ inner: I) -> some View {
    VStack(alignment: .mark, spacing: 0) { inner.background(Reader(tag: "V")); box(6, 1, "C") }
}
@MainActor func outerV<I: View>(_ a: VerticalAlignment, _ inner: I) -> some View {
    HStack(alignment: a, spacing: 0) { inner.background(Reader(tag: "V")); box(1, 6, "C") }
}
@MainActor func gl() -> some View { box(1, 1, "G").alignmentGuide(.leading) { _ in 5 } }
@MainActor func gm() -> some View { box(1, 1, "G").alignmentGuide(.mark) { _ in 5 } }

struct OneViewBody: View { var body: some View { gl() } }
struct TwoViewBody: View { var body: some View { gl(); box(6, 1, "S") } }
struct BranchBody: View { let flag: Bool; var body: some View { if flag { gl() } else { box(1, 1, "G") } } }
struct OptionalBody: View { let flag: Bool; var body: some View { if flag { gl() } } }

@MainActor func runA() {
    print("== A1: .leading out of statically-one-view containers; outer VStack(.leading){inner; C}: C.x=5 reported")
    show("VStackLayout(leading){G}", outer(VStackLayout(alignment: .leading, spacing: 0) { gl() }), ["G", "V", "C"])
    show("HStackLayout{G}", outer(HStackLayout(spacing: 0) { gl() }), ["G", "V", "C"])
    show("ZStackLayout(leading){G}", outer(ZStackLayout(alignment: .leading) { gl() }), ["G", "V", "C"])
    show("SimpleColumn{G}", outer(SimpleColumn { gl() }), ["G", "V", "C"])
    show("HStack{G}", outer(HStack(spacing: 0) { gl() }), ["G", "V", "C"])
    show("Group{G} in VStack", outer(VStack(spacing: 0) { Group { gl() } }), ["G", "V", "C"])
    show("VStack{OneViewBody()}", outer(VStack(spacing: 0) { OneViewBody() }), ["G", "V", "C"])
    show("VStack{TwoViewBody()}", outer(VStack(alignment: .leading, spacing: 0) { TwoViewBody() }), ["G", "V", "C"])
    show("VStack{G.padding(0)}", outer(VStack(spacing: 0) { gl().padding(0) }), ["G", "V", "C"])
    show("VStack{BranchBody(true)}", outer(VStack(spacing: 0) { BranchBody(flag: true) }), ["G", "V", "C"])
    show("VStack{OptionalBody(true)}", outer(VStack(spacing: 0) { OptionalBody(flag: true) }), ["G", "V", "C"])
    show("VStack{if true {G}}", outer(VStack(spacing: 0) { if true { gl() } }), ["G", "V", "C"])
    show("VStack{if/else G}", outer(VStack(spacing: 0) { if true { gl() } else { box(1, 1, "G") } }), ["G", "V", "C"])
    show("VStack{VStack{G}}", outer(VStack(spacing: 0) { VStack(spacing: 0) { gl() } }), ["G", "V", "C"])
    show("BranchBody(true) bare", outer(BranchBody(flag: true)), ["G", "V", "C"])
    show("OptionalBody(true) bare", outer(OptionalBody(flag: true)), ["G", "V", "C"])
    show("TwoViewBody().padding(0) bare", outer(TwoViewBody().padding(0)), ["G", "S", "V", "C"])
    print("== A2: baselines out of rows, ZStacks and layouts; outer HStack(.xTextBaseline){inner; C 1x6}")
    for (name, a) in [("firstTextBaseline", VerticalAlignment.firstTextBaseline), ("lastTextBaseline", .lastTextBaseline)] {
        let g = { box(1, 1, "G").alignmentGuide(a) { _ in 5 } }
        show("\(name): control HStack{S 1x1; T 1x1}", outerV(a, HStack(spacing: 0) { box(1, 1, "S"); box(1, 1, "T") }), ["S", "V", "C"])
        show("\(name): HStack{G 5; S}", outerV(a, HStack(spacing: 0) { g(); box(1, 1, "S") }), ["G", "V", "C"])
        show("\(name): ZStack{G 5; S}", outerV(a, ZStack { g(); box(1, 1, "S") }), ["G", "V", "C"])
        show("\(name): VStackLayout{G 5; S}", outerV(a, VStackLayout(spacing: 0) { g(); box(6, 1, "S") }), ["G", "V", "C"])
        show("\(name): HStackLayout{G 5; S}", outerV(a, HStackLayout(spacing: 0) { g(); box(1, 1, "S") }), ["G", "V", "C"])
        show("\(name): SimpleColumn{G 5; S}", outerV(a, SimpleColumn { g(); box(6, 1, "S") }), ["G", "V", "C"])
        show("\(name): AnyLayout(VStackLayout){G 5; S}", outerV(a, AnyLayout(VStackLayout(spacing: 0)) { g(); box(6, 1, "S") }), ["G", "V", "C"])
    }
    print("== A3: custom guide out of HStackLayout, ZStackLayout, SimpleRow")
    show("HStackLayout{G mark 5; S}", outerMark(HStackLayout(spacing: 0) { gm(); box(6, 1, "S") }), ["G", "V", "C"])
    show("ZStackLayout(leading){G mark 5; S}", outerMark(ZStackLayout(alignment: .leading) { gm(); box(6, 1, "S") }), ["G", "V", "C"])
    show("SimpleRow{S; G mark 5}", outerMark(SimpleRow { box(6, 1, "S"); gm() }), ["G", "V", "C"])
}

@MainActor func runB() {
    print("== B: .leading guide 5 on G (w1) through a wrapper; outer VStack(.leading){inner; C w6}")
    show("G.frame(w10, leading)", outer(gl().frame(width: 10, alignment: .leading)), ["G", "V", "C"])
    show("G.frame(w10, center)", outer(gl().frame(width: 10, alignment: .center)), ["G", "V", "C"])
    show("G.frame(w10, trailing)", outer(gl().frame(width: 10, alignment: .trailing)), ["G", "V", "C"])
    show("G.frame(w10 h3, bottomTrailing)", outer(gl().frame(width: 10, height: 3, alignment: .bottomTrailing)), ["G", "V", "C"])
    show("G.frame(minWidth 10, center)", outer(gl().frame(minWidth: 10, alignment: .center)), ["G", "V", "C"])
    show("G.frame(maxWidth inf, trailing).frame(w 20)", outer(gl().frame(maxWidth: .infinity, alignment: .trailing).frame(width: 20)), ["G", "V", "C"])
    show("G.border(2)", outer(gl().border(Color.red, width: 2)), ["G", "V", "C"])
    show("G.offset(x 3)", outer(gl().offset(x: 3)), ["G", "V", "C"])
    show("G.offset(x 3 y 2)", outer(gl().offset(x: 3, y: 2)), ["G", "V", "C"])
    show("G.overlay{box 10x1}", outer(gl().overlay { box(10, 1, "O") }), ["G", "O", "V", "C"])
    show("G.background{box 10x1}", outer(gl().background { box(10, 1, "O") }), ["G", "O", "V", "C"])
    show("G.padding(.leading, 2)", outer(gl().padding(.leading, 2)), ["G", "V", "C"])
    show("G.fixedSize()", outer(gl().fixedSize()), ["G", "V", "C"])
    show("G.position(x 3 y 0)", outer(gl().position(x: 3, y: 0).frame(width: 10, height: 2)), ["G", "V", "C"])
    show("G.foregroundStyle(.red)", outer(gl().foregroundStyle(.red)), ["G", "V", "C"])
    show("G.id(1)", outer(gl().id(1)), ["G", "V", "C"])
    print("== B2: a frame's guide where the stack aligns on the same guide as the frame's alignment, center")
    show("outerC: G(center 0).frame(w10, center)", outerC(box(1, 1, "G").alignmentGuide(HorizontalAlignment.center) { _ in 0 }.frame(width: 10, alignment: .center)), ["G", "V", "C"])
    show("outerT: G(trailing 0).frame(w10, trailing)", outerT(box(1, 1, "G").alignmentGuide(.trailing) { _ in 0 }.frame(width: 10, alignment: .trailing)), ["G", "V", "C"])
    print("== B3: vertical .top guide 5 on G (h1) through a wrapper; outer HStack(.top){inner; C 1x6}")
    let gt = { box(1, 1, "G").alignmentGuide(.top) { _ in 5 } }
    show("ref G", outerV(.top, gt()), ["G", "V", "C"])
    show("G.frame(h4, top)", outerV(.top, gt().frame(height: 4, alignment: .top)), ["G", "V", "C"])
    show("G.frame(h4, center)", outerV(.top, gt().frame(height: 4, alignment: .center)), ["G", "V", "C"])
    show("G.frame(h4, bottom)", outerV(.top, gt().frame(height: 4, alignment: .bottom)), ["G", "V", "C"])
    show("G.border(2)", outerV(.top, gt().border(Color.red, width: 2)), ["G", "V", "C"])
    show("G.offset(y 2)", outerV(.top, gt().offset(y: 2)), ["G", "V", "C"])
}


@MainActor func runC() {
    print("== C: more shapes; outer VStack(.leading){inner; C w6}: C.x=5 reported")
    show("VStack{AnyView(G)}", outer(VStack(spacing: 0) { AnyView(gl()) }), ["G", "V", "C"])
    show("AnyView(G) bare", outer(AnyView(gl())), ["G", "V", "C"])
    show("VStack{G; EmptyView().padding()}", outer(VStack(spacing: 0) { gl(); EmptyView().padding() }), ["G", "V", "C"])
    show("VStack{G.onAppear{}}", outer(VStack(spacing: 0) { gl().onAppear {} }), ["G", "V", "C"])
    show("Grid{GridRow{G}}", outer(Grid(horizontalSpacing: 0, verticalSpacing: 0) { GridRow { gl() } }), ["G", "V", "C"])
    show("Grid{GridRow{G; S}}", outer(Grid(horizontalSpacing: 0, verticalSpacing: 0) { GridRow { gl(); box(6, 1, "S") } }), ["G", "V", "C"])
    show("Grid{GridRow{G mark; S}} (mark)", outerMark(Grid(horizontalSpacing: 0, verticalSpacing: 0) { GridRow { gm(); box(6, 1, "S") } }), ["G", "V", "C"])
    for (name, a) in [("firstTextBaseline", VerticalAlignment.firstTextBaseline)] {
        let g = { box(1, 1, "G").alignmentGuide(a) { _ in 5 } }
        show("\(name): Grid{GridRow{G 5; S}}", outerV(a, Grid(horizontalSpacing: 0, verticalSpacing: 0) { GridRow { g(); box(1, 1, "S") } }), ["G", "V", "C"])
        show("\(name): VStack{G 5; S}", outerV(a, VStack(spacing: 0) { g(); box(1, 1, "S") }), ["G", "V", "C"])
        show("\(name): VStack{G 5; S 3}", outerV(a, VStack(spacing: 0) { g(); box(1, 1, "S").alignmentGuide(a) { _ in 3 } }), ["G", "S", "V", "C"])
    }
}

@MainActor func runD() {
    print("== D: EmptyView under modifiers in VStack(spacing 0){A 6x1; inner; B 6x1}: B.y = 1 + inner height")
    func col<I: View>(_ inner: I) -> some View { VStack(alignment: .leading, spacing: 0) { box(6, 1, "A"); inner; box(6, 1, "B") } }
    show("EmptyView()", col(EmptyView()), ["A", "B"])
    show("EmptyView().frame(height 5)", col(EmptyView().frame(height: 5)), ["A", "B"])
    show("EmptyView().padding(2)", col(EmptyView().padding(2)), ["A", "B"])
    show("EmptyView().overlay{box 4x2 O}", col(EmptyView().overlay { box(4, 2, "O") }), ["A", "O", "B"])
    show("EmptyView().background{box 4x2 O}", col(EmptyView().background { box(4, 2, "O") }), ["A", "O", "B"])
    show("EmptyView().overlay{box}.frame(height 3)", col(EmptyView().overlay { box(4, 2, "O") }.frame(height: 3)), ["A", "O", "B"])
    show("EmptyView().border(.red)", col(EmptyView().border(Color.red)), ["A", "B"])
    show("EmptyView().frame(width 5, height 5).background(Color.red)", col(EmptyView().frame(width: 5, height: 5).background(Color.red)), ["A", "B"])
    show("Group{EmptyView()}.frame(height 5)", col(Group { EmptyView() }.frame(height: 5)), ["A", "B"])
    show("EmptyView().id(1).frame(height 5)", col(EmptyView().id(1).frame(height: 5)), ["A", "B"])
    show("EmptyView().onAppear{}.frame(height 5)", col(EmptyView().onAppear {}.frame(height: 5)), ["A", "B"])
    show("HStack{A; EmptyView().frame(width 5); B} row", HStack(spacing: 0) { box(1, 1, "A"); EmptyView().frame(width: 5); box(1, 1, "B") }, ["A", "B"])
    print("== D2: a frame with an ideal and no maximum, offered nothing on the width (fixedSize, horizontal ScrollView)")
    show("box(5).frame(idealWidth 10).fixedSize()", box(5, 1, "T").frame(idealWidth: 10).background(Reader(tag: "F")).fixedSize(), ["T", "F"])
    show("ScrollView(.horizontal){box(5).frame(idealWidth 10)}", ScrollView(.horizontal) { box(5, 1, "T").frame(idealWidth: 10).background(Reader(tag: "F")) }.frame(width: 40, height: 3), ["T", "F"])
    show("HStack{box(5).frame(idealWidth 10); box(3)}.fixedSize()", HStack(spacing: 0) { box(5, 1, "T").frame(idealWidth: 10).background(Reader(tag: "F")); box(3, 1, "S") }.fixedSize(), ["T", "F", "S"])
    show("box(5).frame(idealHeight 3).fixedSize()", box(5, 1, "T").frame(idealHeight: 3).background(Reader(tag: "F")).fixedSize(), ["T", "F"])
    show("VStack{box(5).frame(idealHeight 3); box(3)} in 200 tall", VStack(spacing: 0) { box(5, 1, "T").frame(idealHeight: 3).background(Reader(tag: "F")); box(3, 1, "S") }, ["T", "F", "S"])
}

setlinebuf(stdout)
let which = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "A"
MainActor.assumeIsolated {
    switch which {
    case "A": runA()
    case "B": runB()
    case "C": runC()
    case "D": runD()
    default: print("unknown case")
    }
}
