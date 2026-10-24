import SwiftUI
import AppKit

// DECB/B30: which anchor wins when a transaction's scrollTargetAnchor and a
// call's own anchor disagree? Offscreen NSHostingView; reads the clip origin.

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
@MainActor final class Box { static var proxy: ScrollViewProxy?; static var pos = ScrollPosition(idType: Int.self) }

struct Rows: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { i in Text("row \(i)").frame(height: 20).id(i) } }
            }
            .onAppear { MainActor.assumeIsolated { Box.proxy = proxy } }
        }
    }
}
struct PosRows: View {
    @State var pos = ScrollPosition(idType: Int.self)
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { i in Text("row \(i)").frame(height: 20).id(i) } }
                .scrollTargetLayout()
        }
        .scrollPosition($pos)
        .onAppear { MainActor.assumeIsolated { PosBox.set = { p in pos = p }; PosBox.scroll = { id, a in pos.scrollTo(id: id, anchor: a) } } }
    }
}
@MainActor final class PosBox { static var set: ((ScrollPosition) -> Void)?; static var scroll: ((Int, UnitPoint?) -> Void)? }

@MainActor func origin(_ h: NSView) -> Int {
    guard let sv = findScrollView(h) else { return -999 }
    return Int(sv.contentView.bounds.origin.y)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func caseProxy(_ name: String, _ body: @MainActor (ScrollViewProxy) -> Void) {
        let h = host(Rows()); spin()
        guard let p = Box.proxy else { print(name, "no proxy"); return }
        body(p); spin()
        print("proxy ", name, "originY =", origin(h), "(row 50 top = 1000; centred = 910; bottom = 820)")
    }
    caseProxy("call .top, no txn                ") { p in p.scrollTo(50, anchor: .top) }
    caseProxy("call .bottom, no txn             ") { p in p.scrollTo(50, anchor: .bottom) }
    caseProxy("call nil, no txn                 ") { p in p.scrollTo(50) }
    caseProxy("call nil, txn .bottom            ") { p in var t = Transaction(); t.scrollTargetAnchor = .bottom; withTransaction(t) { p.scrollTo(50) } }
    caseProxy("call nil, txn .top               ") { p in var t = Transaction(); t.scrollTargetAnchor = .top; withTransaction(t) { p.scrollTo(50) } }
    caseProxy("call nil, txn .center            ") { p in var t = Transaction(); t.scrollTargetAnchor = .center; withTransaction(t) { p.scrollTo(50) } }
    caseProxy("call .top, txn .bottom           ") { p in var t = Transaction(); t.scrollTargetAnchor = .bottom; withTransaction(t) { p.scrollTo(50, anchor: .top) } }
    caseProxy("call .center, txn .top           ") { p in var t = Transaction(); t.scrollTargetAnchor = .top; withTransaction(t) { p.scrollTo(50, anchor: .center) } }
    @MainActor func casePos(_ name: String, _ body: @MainActor () -> Void) {
        let h = host(PosRows()); spin()
        body(); spin()
        print("pos   ", name, "originY =", origin(h))
    }
    casePos("scrollTo(id:50, anchor:.top), no txn       ") { PosBox.scroll?(50, .top) }
    casePos("scrollTo(id:50, anchor:.center), no txn    ") { PosBox.scroll?(50, .center) }
    casePos("scrollTo(id:50, anchor:nil), txn .top      ") { var t = Transaction(); t.scrollTargetAnchor = .top; withTransaction(t) { PosBox.scroll?(50, nil) } }
    casePos("scrollTo(id:50, anchor:.bottom), txn .top  ") { var t = Transaction(); t.scrollTargetAnchor = .top; withTransaction(t) { PosBox.scroll?(50, .bottom) } }
    casePos("scrollTo(id:50, anchor:nil), no txn        ") { PosBox.scroll?(50, nil) }
    casePos("scrollTo(id:50, anchor:nil), txn .bottom   ") { var t = Transaction(); t.scrollTargetAnchor = .bottom; withTransaction(t) { PosBox.scroll?(50, nil) } }
    casePos("scrollTo(id:50, anchor:.top), txn .bottom  ") { var t = Transaction(); t.scrollTargetAnchor = .bottom; withTransaction(t) { PosBox.scroll?(50, .top) } }
}
