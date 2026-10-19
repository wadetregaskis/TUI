import SwiftUI
import AppKit

// B-D2S-7, the horizontal case: a carousel of 60-point cards in a
// ScrollView(.horizontal) with leading and trailing content margins, under
// `.viewAligned` and `.paging`; a resize of the window makes SwiftUI consult
// the behaviour. Same harness as `margins.swift`.

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

struct Carousel<B: ScrollTargetBehavior>: View {
    let behavior: B
    let leading: CGFloat
    let trailing: CGFloat
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { i in
                    Text("\(i)").frame(width: 60, height: 40).background(i % 2 == 0 ? Color.gray : Color.white)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.leading, leading, for: .scrollContent)
        .contentMargins(.trailing, trailing, for: .scrollContent)
        .scrollTargetBehavior(Logged(base: behavior))
        .scrollIndicators(.never)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run<B: ScrollTargetBehavior>(_ name: String, _ b: B, leading: CGFloat, trailing: CGFloat, start: CGFloat) {
        log = []
        let (h, w) = host(Carousel(behavior: b, leading: leading, trailing: trailing), size: CGSize(width: 200, height: 60))
        spin()
        scrollClip(h, to: NSPoint(x: start, y: 0)); spin()
        let before = origin(h)
        log = []
        w.setContentSize(CGSize(width: 210, height: 60))
        h.layoutSubtreeIfNeeded(); spin()
        print("== \(name): origin \(before) -> resize to 210×60 -> \(origin(h))")
        for l in log { print(l) }
        w.orderOut(nil)
    }
    for (l, t) in [(0.0, 0.0), (20.0, 20.0), (40.0, 0.0), (0.0, 40.0)] {
        for start: CGFloat in [50, 110, 200, 290] {
            run("viewAligned, leading \(Int(l)) trailing \(Int(t)), start \(Int(start))", .viewAligned, leading: l, trailing: t, start: start)
        }
        for start: CGFloat in [50, 110, 200, 290, 380] {
            run("paging, leading \(Int(l)) trailing \(Int(t)), start \(Int(start))", .paging, leading: l, trailing: t, start: start)
        }
    }
}
