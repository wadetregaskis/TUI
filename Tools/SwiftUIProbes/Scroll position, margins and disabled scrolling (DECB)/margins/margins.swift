import SwiftUI
import AppKit

// DECB/B24: where does an NSScroller go under SwiftUI contentMargins, by placement?
// Offscreen NSHostingView; reads the NSScrollView's scrollerInsets/contentInsets and the
// vertical scroller's frame, for overlay and legacy scroller styles.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 200)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func findScrollView(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScrollView(c) { return s } }
    return nil
}
func f(_ r: NSRect) -> String { "x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width)) h=\(Int(r.height))" }
func ins(_ e: NSEdgeInsets) -> String { "t=\(Int(e.top)) l=\(Int(e.left)) b=\(Int(e.bottom)) r=\(Int(e.right))" }

@MainActor final class Probe { static var contentFrame: CGRect = .zero }
struct Content: View {
    var body: some View {
        VStack(spacing: 0) { ForEach(0..<60) { i in Text("row \(i)").frame(maxWidth: .infinity, alignment: .leading) } }
            .background(GeometryReader { p in
                let r = p.frame(in: .global)
                let _ = MainActor.assumeIsolated { Probe.contentFrame = r }
                Color.clear
            })
    }
}

@MainActor func run<V: View>(_ name: String, _ style: NSScroller.Style, _ v: V) {
    let h = host(v)
    spin()
    guard let sv = findScrollView(h) else { print(name, "no NSScrollView"); return }
    sv.scrollerStyle = style
    sv.tile()
    h.layoutSubtreeIfNeeded()
    spin(0.1)
    let vs = sv.verticalScroller
    print(name, style == .legacy ? "legacy" : "overlay",
          "| scrollView", f(sv.frame), "| scrollerInsets", ins(sv.scrollerInsets),
          "| contentInsets", ins(sv.contentInsets), "auto", sv.automaticallyAdjustsContentInsets,
          "| vScroller", vs.map { f($0.frame) } ?? "nil", "hidden", vs?.isHidden ?? true,
          "| clip", f(sv.contentView.frame), "docVisible", f(sv.documentVisibleRect), "| content(global) x=\(Int(Probe.contentFrame.minX)) w=\(Int(Probe.contentFrame.width)) y=\(Int(Probe.contentFrame.minY))")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    for style in [NSScroller.Style.overlay, .legacy] {
        run("none          ", style, ScrollView { Content() })
        run("auto  trail20 ", style, ScrollView { Content() }.contentMargins(.trailing, 20))
        run("auto  vert30  ", style, ScrollView { Content() }.contentMargins(.vertical, 30))
        run("ind   trail20 ", style, ScrollView { Content() }.contentMargins(.trailing, 20, for: .scrollIndicators))
        run("ind   vert30  ", style, ScrollView { Content() }.contentMargins(.vertical, 30, for: .scrollIndicators))
        run("cont  trail20 ", style, ScrollView { Content() }.contentMargins(.trailing, 20, for: .scrollContent))
        run("cont  vert30  ", style, ScrollView { Content() }.contentMargins(.vertical, 30, for: .scrollContent))
    }
}
