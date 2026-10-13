import SwiftUI
import AppKit

// SCROLLANCHOR: what SwiftUI's lazy stack does with the row at its top when the
// rows are REORDERED rather than inserted or removed. Same harness as
// hold.swift: offscreen NSHostingView, 300x200, rows 20 high, 40 rows, scrolled
// to row 10 (origin 200); prints the origin before and after, and the row the
// origin falls on (all rows are 20 high, so it is the row at that index).

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 200)
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
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? {
    if let s = v as? T { return s }
    for c in v.subviews { if let s = find(c, t) { return s } }
    return nil
}
@MainActor func origin(_ h: NSView) -> Int {
    guard let sv = find(h, NSScrollView.self) else { return -999 }
    return Int(sv.contentView.bounds.origin.y)
}
@MainActor func scrollClip(_ h: NSView, to y: CGFloat) {
    guard let sv = find(h, NSScrollView.self) else { return }
    sv.contentView.scroll(to: NSPoint(x: 0, y: y))
    sv.reflectScrolledClipView(sv.contentView)
}

@MainActor final class Ctl {
    static var setRows: (([Int]) -> Void)?
    static var rows: [Int] = []
}

struct Rows: View {
    @State var rows: [Int] = Array(0..<40)
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.self) { i in Text("row \(i)").frame(height: 20) }
            }
        }
        .onAppear {
            MainActor.assumeIsolated {
                Ctl.setRows = { r in rows = r; Ctl.rows = r }
                Ctl.rows = rows
            }
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run(_ name: String, rows: [Int]) {
        let h = host(Rows()); spin()
        scrollClip(h, to: 200); spin()
        let before = origin(h)
        Ctl.setRows?(rows)
        spin()
        let after = origin(h)
        let top = after / 20 < Ctl.rows.count ? "row \(Ctl.rows[after / 20])" : "past end"
        print(name.padding(toLength: 52, withPad: " ", startingAt: 0), "origin", before, "->", after, "| top", top)
    }
    let base = Array(0..<40)
    run("1 reverse every row", rows: base.reversed())
    run("2 move the top row (10) to the end", rows: base.filter { $0 != 10 } + [10])
    run("3 move row 30 (below the screen) to the start", rows: [30] + base.filter { $0 != 30 })
    run("4 move row 0 (above) to the end", rows: base.filter { $0 != 0 } + [0])
    run("5 swap rows 10 and 11", rows: Array(0..<10) + [11, 10] + Array(12..<40))
    run("6 move rows 0-4 (above) to the end", rows: Array(5..<40) + Array(0..<5))
}
