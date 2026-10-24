import SwiftUI
import AppKit

@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<AnyView> {
    let h = NSHostingView(rootView: AnyView(v))
    h.frame = NSRect(origin: .zero, size: size)
    h.layoutSubtreeIfNeeded()
    return h
}

@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}

struct Probe: View {
    let tag: String
    var body: some View {
        GeometryReader { g in
            let _ = print(tag, "body: frame(in: .scrollView)=", g.frame(in: .scrollView),
                          " bounds(of: .scrollView)=", String(describing: g.bounds(of: .scrollView)),
                          " frame(in: .named(\"content\"))=", g.frame(in: .named("content")),
                          " frame(in: .named(\"sv\"))=", g.frame(in: .named("sv")),
                          " frame(in: .scrollView(axis: .vertical))=", g.frame(in: .scrollView(axis: .vertical)),
                          " frame(in: .scrollView(axis: .horizontal))=", g.frame(in: .scrollView(axis: .horizontal)),
                          " global=", g.frame(in: .global))
            Color.clear
        }
        .frame(height: 20)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { print(tag, "onGeometryChange .scrollView =", $0) }
    }
}

struct A: View {
    @State var pos = ScrollPosition(y: 40)
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 40)
                Probe(tag: "A")
                Color.blue.frame(height: 200)
            }
            .coordinateSpace(.named("content"))
        }
        .scrollPosition($pos)
        .coordinateSpace(.named("sv"))
        .frame(width: 100, height: 100).padding(.leading, 7).padding(.top, 9)
    }
}

struct B: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 40)
                Probe(tag: "B")
                Color.blue.frame(height: 200)
            }
            .coordinateSpace(.named("content"))
        }
        .coordinateSpace(.named("sv"))
        .frame(width: 100, height: 100).padding(.leading, 7).padding(.top, 9)
    }
}

@MainActor func run() {
    print("== (a) ScrollPosition(y: 40)")
    let ha = host(A(), size: CGSize(width: 107, height: 109))
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    ha.layoutSubtreeIfNeeded()
    if let s = findScroll(ha) { print("A clip origin", s.contentView.bounds.origin) }

    print("== (b) scrolled by NSScrollView to y=40")
    let hb = host(B(), size: CGSize(width: 107, height: 109))
    if let s = findScroll(hb) {
        s.contentView.scroll(to: NSPoint(x: 0, y: 40))
        s.reflectScrolledClipView(s.contentView)
        print("B clip origin", s.contentView.bounds.origin)
    } else { print("B: no NSScrollView") }
    hb.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    hb.layoutSubtreeIfNeeded()
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
