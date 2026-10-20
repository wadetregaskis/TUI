import SwiftUI
import AppKit

// A `.scrollPosition(id:)` bound to an outer ScrollView whose content holds a
// nested ScrollView or a List (lane SCROLL review, 2026-10-19). Asks three
// things: does an id the app writes reach the nested scrollable; does the
// nested one follow the outer view's write-backs; and does the nested one's
// own scroll write into the binding. Prints every NSScrollView's clip origin
// (depth first: the outer one first), the bound id, and the writes made.
// A live scroll is posted as AppKit reports a user's: the live-scroll
// notifications around a move of the clip view (a bare move writes nothing
// back, even on the outer view).

@MainActor var keep: [NSWindow] = []
@Observable final class Model {
    var id: Int? = nil { didSet { writes.append(id) } }
    @ObservationIgnored var writes: [Int?] = []
}
nonisolated(unsafe) let model = Model()

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
@MainActor func scrollViews(_ v: NSView, into out: inout [NSScrollView]) {
    if let s = v as? NSScrollView { out.append(s) }
    for c in v.subviews { scrollViews(c, into: &out) }
}
@MainActor func origins(_ h: NSView) -> String {
    var svs: [NSScrollView] = []
    scrollViews(h, into: &svs)
    return svs.map { "(\(Int($0.contentView.bounds.origin.x)), \(Int($0.contentView.bounds.origin.y)))" }
        .joined(separator: " ")
}
@MainActor func liveScroll(_ sv: NSScrollView, by dy: CGFloat) {
    let nc = NotificationCenter.default
    nc.post(name: NSScrollView.willStartLiveScrollNotification, object: sv)
    spin(0.05)
    let o = sv.contentView.bounds.origin
    sv.contentView.scroll(to: NSPoint(x: o.x, y: o.y + dy))
    sv.reflectScrolledClipView(sv.contentView)
    nc.post(name: NSScrollView.didLiveScrollNotification, object: sv)
    spin(0.05)
    nc.post(name: NSScrollView.didEndLiveScrollNotification, object: sv)
    spin()
}

enum Inner { case none, scrollView, list }

// Thirty 20-point rows (ids 0..<30), then the nested scrollable, 60 points
// tall, over `innerIDs`.
struct Probe: View {
    let inner: Inner
    let innerIDs: Range<Int>
    @Bindable var m: Model
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { i in Text("o\(i)").frame(height: 20) }
                switch inner {
                case .none:
                    EmptyView()
                case .scrollView:
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(innerIDs, id: \.self) { i in Text("i\(i)").frame(height: 20) }
                        }
                        .scrollTargetLayout()
                    }
                    .frame(height: 60)
                case .list:
                    List(innerIDs, id: \.self) { i in Text("i\(i)").frame(height: 20) }
                        .frame(height: 60)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $m.id)
    }
}

@MainActor func request(_ inner: Inner, ids: Range<Int>, set: Int, label: String) {
    model.id = nil
    let h = host(Probe(inner: inner, innerIDs: ids, m: model)); spin()
    model.writes = []
    model.id = set
    spin()
    print(label, "id = \(set):", origins(h), "id", String(describing: model.id), "writes", model.writes.dropFirst())
}

@MainActor func scrolls(_ inner: Inner, ids: Range<Int>, label: String) {
    model.id = nil
    let h = host(Probe(inner: inner, innerIDs: ids, m: model)); spin()
    var svs: [NSScrollView] = []
    scrollViews(h, into: &svs)
    for step in 1...2 {
        model.writes = []
        liveScroll(svs[0], by: 100)
        print(label, "outer scrolled (\(step)):", origins(h), "id", String(describing: model.id), "writes", model.writes)
    }
    if svs.count > 1 {
        model.writes = []
        liveScroll(svs[1], by: 100)
        print(label, "inner scrolled:     ", origins(h), "id", String(describing: model.id), "writes", model.writes)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    print("-- requests")
    request(.none, ids: 0..<0, set: 20, label: "no inner            ")
    request(.scrollView, ids: 100..<200, set: 150, label: "scrollView, disjoint")
    request(.scrollView, ids: 0..<100, set: 20, label: "scrollView, shared  ")
    request(.scrollView, ids: 0..<100, set: 60, label: "scrollView, inner's ")
    request(.list, ids: 100..<200, set: 150, label: "list, disjoint      ")
    request(.list, ids: 0..<100, set: 20, label: "list, shared        ")
    request(.list, ids: 0..<100, set: 60, label: "list, inner's       ")
    print("-- live scrolls (inner ids 0..<100, shared with the outer's 0..<30)")
    scrolls(.none, ids: 0..<0, label: "no inner  ")
    scrolls(.scrollView, ids: 0..<100, label: "scrollView")
    scrolls(.list, ids: 0..<100, label: "list      ")
}
