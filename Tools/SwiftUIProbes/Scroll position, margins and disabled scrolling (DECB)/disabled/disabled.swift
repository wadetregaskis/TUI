import SwiftUI
import AppKit

// DECB/B30: what does SwiftUI do under Transaction.scrollContentOffsetAdjustmentBehavior = .disabled?
// Offscreen NSHostingView, 300x200, rows 20 high; reads the clip origin (y) before and after a change.

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
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func findScrollView(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScrollView(c) { return s } }
    return nil
}
@MainActor func origin(_ h: NSView) -> Int {
    guard let sv = findScrollView(h) else { return -999 }
    return Int(sv.contentView.bounds.origin.y)
}
@MainActor final class Ctl {
    static var setRange: ((Range<Int>) -> Void)?
    static var proxy: ScrollViewProxy?
}
enum Anchor { case none, bottom, bottomSizeChanges }

struct Rows: View {
    let anchor: Anchor
    let lazy: Bool
    let marked: Bool
    @State var range = 0..<20
    @State var pos = ScrollPosition(idType: Int.self)
    var rows: some View {
        ForEach(range, id: \.self) { i in Text("row \(i)").frame(height: 20).id(i) }
    }
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                switch anchor {
                case .none: scroller
                case .bottom: scroller.defaultScrollAnchor(.bottom)
                case .bottomSizeChanges: scroller.defaultScrollAnchor(.bottom, for: .sizeChanges)
                }
            }
            .onAppear { MainActor.assumeIsolated { Ctl.proxy = proxy; Ctl.setRange = { r in range = r } } }
        }
    }
    @ViewBuilder var scroller: some View {
        if marked {
            ScrollView { Group { if lazy { LazyVStack(spacing: 0) { rows } } else { VStack(spacing: 0) { rows } } }.scrollTargetLayout() }
                .scrollPosition($pos)
        } else {
            ScrollView { if lazy { LazyVStack(spacing: 0) { rows } } else { VStack(spacing: 0) { rows } } }
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run(_ name: String, anchor: Anchor, lazy: Bool = true, marked: Bool = false,
                        prepare: @MainActor () -> Void = {}, change: Range<Int>, disabled: Bool) {
        let h = host(Rows(anchor: anchor, lazy: lazy, marked: marked)); spin()
        prepare(); spin()
        let before = origin(h)
        if disabled {
            var t = Transaction(); t.scrollContentOffsetAdjustmentBehavior = .disabled
            withTransaction(t) { Ctl.setRange?(change) }
        } else {
            Ctl.setRange?(change)
        }
        spin()
        print(name.padding(toLength: 60, withPad: " ", startingAt: 0), disabled ? "disabled " : "automatic", "origin", before, "->", origin(h))
    }
    for d in [false, true] {
        run("A defaultScrollAnchor(.bottom), append 5", anchor: .bottom, change: 0..<25, disabled: d)
    }
    for d in [false, true] {
        run("A' defaultScrollAnchor(.bottom) eager VStack, append 5", anchor: .bottom, lazy: false, change: 0..<25, disabled: d)
    }
    for d in [false, true] {
        run("B defaultScrollAnchor(.bottom, for: .sizeChanges), append 5", anchor: .bottomSizeChanges, change: 0..<25, disabled: d)
    }
    for d in [false, true] {
        run("C no anchor, scrolled to bottom by proxy, append 5", anchor: .none,
            prepare: { Ctl.proxy?.scrollTo(19, anchor: .bottom) }, change: 0..<25, disabled: d)
    }
    for d in [false, true] {
        run("D no anchor, row 10 at top by proxy, insert 5 above", anchor: .none,
            prepare: { Ctl.proxy?.scrollTo(10, anchor: .top) }, change: -5..<20, disabled: d)
    }
    for d in [false, true] {
        run("E scrollPosition marked, row 10 at top, insert 5 above", anchor: .none, marked: true,
            prepare: { Ctl.proxy?.scrollTo(10, anchor: .top) }, change: -5..<20, disabled: d)
    }
    for d in [false, true] {
        run("F no anchor, at top (origin 0), append 5", anchor: .none, change: 0..<25, disabled: d)
    }
}
