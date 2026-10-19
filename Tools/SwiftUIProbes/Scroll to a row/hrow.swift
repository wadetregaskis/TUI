import SwiftUI
import AppKit

// SA-45: what `scrollTo` does with a row of a vertical stack inside a purely
// horizontal ScrollView. Rows of different widths, centred (the VStack's
// default) or leading; the request names one row with each anchor. Prints
// the clip view's origin after the request.

@MainActor var keep: [NSWindow] = []
@MainActor final class Ctl { static var proxy: ScrollViewProxy? }
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 200, height: 200)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? {
    if let s = v as? T { return s }
    for c in v.subviews { if let s = find(c, t) { return s } }
    return nil
}
@MainActor func origin(_ h: NSView) -> String {
    guard let sv = find(h, NSScrollView.self) else { return "none" }
    let o = sv.contentView.bounds.origin
    return "(\(Int(o.x)), \(Int(o.y)))"
}

struct Rows: View {
    let alignment: HorizontalAlignment
    // Row i is 100 + 100 * (i % 5) points wide, 20 tall.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: alignment, spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in
                        Color.red.frame(width: CGFloat(100 + 100 * (i % 5)), height: 20).id(i)
                    }
                }
            }
            .onAppear { MainActor.assumeIsolated { Ctl.proxy = proxy } }
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    for alignment in [HorizontalAlignment.center, .leading] {
        for (row, anchor, name) in [(4, nil, "nil"), (4, UnitPoint.leading, "leading"), (4, .trailing, "trailing"),
                                    (4, .center, "center"), (1, .trailing, "trailing"), (0, .leading, "leading")] as [(Int, UnitPoint?, String)] {
            let h = host(Rows(alignment: alignment)); spin()
            let before = origin(h)
            Ctl.proxy?.scrollTo(row, anchor: anchor); spin()
            print(alignment == .center ? "center " : "leading", "row \(row) anchor \(name):", before, "->", origin(h))
        }
    }
}
