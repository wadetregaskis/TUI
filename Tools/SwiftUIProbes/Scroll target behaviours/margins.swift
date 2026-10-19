import SwiftUI
import AppKit

// B-D2S-7: what a scroll target behaviour is handed, and where it lands, under
// `.contentMargins`. A behaviour of the probe's own logs what each call is
// given (container, content, the proposed target) and what the built-in one
// it wraps returns; a resize of the window makes SwiftUI consult it.

@MainActor var keep: [NSWindow] = []
@MainActor var log: [String] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> (NSHostingView<V>, NSWindow) {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return (h, w)
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
    let i = sv.contentView.contentInsets
    return "(\(Int(o.x)), \(Int(o.y))) insets t\(Int(i.top)) l\(Int(i.left)) b\(Int(i.bottom)) r\(Int(i.right))"
}
@MainActor func scrollClip(_ h: NSView, to p: NSPoint) {
    guard let sv = find(h, NSScrollView.self) else { return }
    sv.contentView.scroll(to: p)
    sv.reflectScrolledClipView(sv.contentView)
}
func r(_ rect: CGRect) -> String { "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height)))" }
func s(_ size: CGSize) -> String { "\(Int(size.width))×\(Int(size.height))" }

struct Logged<B: ScrollTargetBehavior>: ScrollTargetBehavior {
    let base: B
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let before = target.rect
        base.updateTarget(&target, context: context)
        let line = "  call: container \(s(context.containerSize)) content \(s(context.contentSize)) "
            + "original \(r(context.originalTarget.rect)) proposed \(r(before)) -> \(r(target.rect))"
        MainActor.assumeIsolated { log.append(line) }
    }
}

enum Kind { case paging, viewAligned }

struct Vertical: View {
    let kind: Kind
    let margins: EdgeInsets
    var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<30, id: \.self) { i in
                Text("row \(i)").frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                    .background(i % 2 == 0 ? Color.gray : Color.white)
            }
        }
        .scrollTargetLayout()
    }
    var body: some View {
        switch kind {
        case .paging:
            ScrollView { rows }
                .contentMargins(.top, margins.top, for: .scrollContent)
                .contentMargins(.bottom, margins.bottom, for: .scrollContent)
                .scrollTargetBehavior(Logged(base: .paging))
                .scrollIndicators(.never)
        case .viewAligned:
            ScrollView { rows }
                .contentMargins(.top, margins.top, for: .scrollContent)
                .contentMargins(.bottom, margins.bottom, for: .scrollContent)
                .scrollTargetBehavior(Logged(base: .viewAligned))
                .scrollIndicators(.never)
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run(_ name: String, kind: Kind, margins: EdgeInsets, start: CGFloat, resize: CGFloat) {
        log = []
        let (h, w) = host(Vertical(kind: kind, margins: margins), size: CGSize(width: 200, height: 100))
        spin()
        scrollClip(h, to: NSPoint(x: 0, y: start)); spin()
        let before = origin(h)
        log = []
        w.setContentSize(CGSize(width: 200, height: resize))
        h.layoutSubtreeIfNeeded(); spin()
        print("== \(name): origin \(before) -> resize to 200×\(Int(resize)) -> \(origin(h))")
        for l in log { print(l) }
        w.orderOut(nil)
    }
    let m = EdgeInsets(top: 30, leading: 0, bottom: 10, trailing: 0)
    let top = EdgeInsets(top: 30, leading: 0, bottom: 0, trailing: 0)
    let bottom = EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0)
    let none = EdgeInsets()
    for start: CGFloat in [7, 37, 60, 100, 150, 220] {
        run("paging, none, start \(Int(start))", kind: .paging, margins: none, start: start, resize: 110)
        run("paging, top 30 bottom 10, start \(Int(start))", kind: .paging, margins: m, start: start, resize: 110)
        run("paging, top 30, start \(Int(start))", kind: .paging, margins: top, start: start, resize: 110)
        run("paging, bottom 10, start \(Int(start))", kind: .paging, margins: bottom, start: start, resize: 110)
    }
    for start: CGFloat in [7, 37, 52, 150] {
        run("viewAligned, none, start \(Int(start))", kind: .viewAligned, margins: none, start: start, resize: 110)
        run("viewAligned, top 30 bottom 10, start \(Int(start))", kind: .viewAligned, margins: m, start: start, resize: 110)
        run("viewAligned, top 30, start \(Int(start))", kind: .viewAligned, margins: top, start: start, resize: 110)
    }
}
