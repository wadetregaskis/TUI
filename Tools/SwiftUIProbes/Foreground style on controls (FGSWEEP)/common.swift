import SwiftUI
import AppKit

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<AnyView> {
    let h = NSHostingView(rootView: AnyView(v))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func g(_ x: ScrollGeometry) -> String {
    "off=\(x.contentOffset) size=\(x.contentSize) insets=(t\(x.contentInsets.top) l\(x.contentInsets.leading) b\(x.contentInsets.bottom) tr\(x.contentInsets.trailing)) container=\(x.containerSize) bounds=\(x.bounds) visible=\(x.visibleRect)"
}
@MainActor func findScrollViews(_ v: NSView) -> [NSScrollView] {
    var out: [NSScrollView] = []
    if let s = v as? NSScrollView { out.append(s) }
    for c in v.subviews { out += findScrollViews(c) }
    return out
}
