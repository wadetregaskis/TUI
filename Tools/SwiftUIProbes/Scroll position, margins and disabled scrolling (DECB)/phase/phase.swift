import SwiftUI
import AppKit

// DECB/B27: what velocity does SwiftUI put in ScrollPhaseChangeContext at each change it can be made to
// produce offscreen (an animated scrollTo; a wheel event sent straight to the NSScrollView)?

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
@MainActor func spin(_ s: Double = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func findScrollView(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScrollView(c) { return s } }
    return nil
}
@MainActor final class Ctl { static var proxy: ScrollViewProxy? }

struct Rows: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { i in Text("row \(i)").frame(height: 20).id(i) } }
            }
            .onScrollPhaseChange { old, new, ctx in
                print("  phase", old, "->", new, "velocity", ctx.velocity.map { "(\($0.dx), \($0.dy))" } ?? "nil")
            }
            .onAppear { MainActor.assumeIsolated { Ctl.proxy = proxy } }
        }
    }
}

@MainActor func wheel(_ sv: NSScrollView, dy: Int32, phase: Int64, momentum: Int64, continuous: Bool) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    let loc = sv.convert(NSPoint(x: 150, y: 100), to: nil)
    e.location = sv.window!.convertPoint(toScreen: loc)
    if let ns = NSEvent(cgEvent: e) { sv.scrollWheel(with: ns) }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    print("case 1: animated scrollTo(50)")
    do {
        let h = host(Rows()); spin()
        withAnimation(.linear(duration: 0.3)) { Ctl.proxy?.scrollTo(50, anchor: .top) }
        spin(1.0)
        _ = h
    }
    print("case 2: discrete wheel (no phases), 5 events, sent to NSScrollView.scrollWheel")
    do {
        let h = host(Rows()); spin()
        if let sv = findScrollView(h) {
            for _ in 0..<5 { wheel(sv, dy: -40, phase: 0, momentum: 0, continuous: false); spin(0.03) }
            spin(1.0)
            print("  origin", Int(sv.contentView.bounds.origin.y))
        }
    }
    print("case 3: trackpad-like wheel (began, changed x4, ended, momentum begin/continue/end)")
    do {
        let h = host(Rows()); spin()
        if let sv = findScrollView(h) {
            // kCGScrollPhaseBegan=1, Changed=2, Ended=4; momentum: Begin=1, Continue=2, End=3
            wheel(sv, dy: 0, phase: 1, momentum: 0, continuous: true); spin(0.016)
            for _ in 0..<4 { wheel(sv, dy: -30, phase: 2, momentum: 0, continuous: true); spin(0.016) }
            wheel(sv, dy: 0, phase: 4, momentum: 0, continuous: true); spin(0.016)
            wheel(sv, dy: -20, phase: 0, momentum: 1, continuous: true); spin(0.016)
            for _ in 0..<3 { wheel(sv, dy: -10, phase: 0, momentum: 2, continuous: true); spin(0.016) }
            wheel(sv, dy: 0, phase: 0, momentum: 3, continuous: true)
            spin(1.0)
            print("  origin", Int(sv.contentView.bounds.origin.y))
        }
    }
}
