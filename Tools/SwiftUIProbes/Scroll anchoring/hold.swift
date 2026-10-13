import SwiftUI
import AppKit

// SCROLLANCHOR / B30: with no scroll position bound, what does SwiftUI do to
// the rows on screen when the content above the top visible row changes?
// Offscreen NSHostingView, 300x200, rows 20 high (10 on screen), 40 rows.
// Prints the scroll view's clip origin (y) before and after one change, and
// the id of the row drawn at the viewport's top (from the origin for a
// stack, from the NSTableView for a List).

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
    static var setTall: ((Set<Int>) -> Void)?
    static var rows: [Int] = []
    static var proxy: ScrollViewProxy?
}

enum Kind { case lazy, eager, list }
enum Anchor: String {
    case none, top, topSizeChanges, bottom, bottomSizeChanges, center, centerSizeChanges
}

struct Rows: View {
    let kind: Kind
    let anchor: Anchor
    @State var rows: [Int] = Array(0..<40)
    @State var tall: Set<Int> = []
    @ViewBuilder var content: some View {
        ForEach(rows, id: \.self) { i in
            Text("row \(i)").frame(height: tall.contains(i) ? 60 : 20).id(i)
        }
    }
    @ViewBuilder var scroller: some View {
        switch kind {
        case .lazy: ScrollView { LazyVStack(spacing: 0) { content } }
        case .eager: ScrollView { VStack(spacing: 0) { content } }
        case .list: List { content }
        }
    }
    @ViewBuilder var anchored: some View {
        switch anchor {
        case .none: scroller
        case .top: scroller.defaultScrollAnchor(.top)
        case .topSizeChanges: scroller.defaultScrollAnchor(.top, for: .sizeChanges)
        case .bottom: scroller.defaultScrollAnchor(.bottom)
        case .bottomSizeChanges: scroller.defaultScrollAnchor(.bottom, for: .sizeChanges)
        case .center: scroller.defaultScrollAnchor(.center)
        case .centerSizeChanges: scroller.defaultScrollAnchor(.center, for: .sizeChanges)
        }
    }
    var body: some View {
        ScrollViewReader { proxy in
            anchored.onAppear {
                MainActor.assumeIsolated {
                    Ctl.proxy = proxy
                    Ctl.setRows = { r in rows = r; Ctl.rows = r }
                    Ctl.setTall = { t in tall = t }
                    Ctl.rows = rows
                }
            }
        }
    }
}

/// The id of the row at the viewport's top.
@MainActor func topRow(_ h: NSView, kind: Kind, tall: Set<Int>) -> String {
    if kind == .list {
        guard let table = find(h, NSTableView.self), let clip = table.enclosingScrollView?.contentView
        else { return "?" }
        let index = table.row(at: NSPoint(x: 1, y: clip.bounds.origin.y + clip.contentInsets.top + 1))
        return index >= 0 && index < Ctl.rows.count ? "row \(Ctl.rows[index])" : "index \(index)"
    }
    var y = 0
    let o = origin(h)
    for id in Ctl.rows {
        let height = tall.contains(id) ? 60 : 20
        if o < y + height { return "row \(id)+\(o - y)" }
        y += height
    }
    return "past end"
}

enum Prepare { case scrollTo(CGFloat), proxyTop(Int), stay }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    @MainActor func run(_ name: String, kind: Kind = .lazy, anchor: Anchor = .none,
                        prepare: Prepare, rows: [Int]? = nil, tall: Set<Int> = []) {
        for disabled in [false, true] {
            let h = host(Rows(kind: kind, anchor: anchor)); spin()
            switch prepare {
            case .scrollTo(let y): scrollClip(h, to: y)
            case .proxyTop(let id): Ctl.proxy?.scrollTo(id, anchor: .top)
            case .stay: break
            }
            spin()
            let before = (origin(h), topRow(h, kind: kind, tall: []))
            let change = {
                if let rows { Ctl.setRows?(rows) }
                if !tall.isEmpty { Ctl.setTall?(tall) }
            }
            if disabled {
                var t = Transaction(); t.scrollContentOffsetAdjustmentBehavior = .disabled
                withTransaction(t) { change() }
            } else {
                change()
            }
            spin()
            print(name.padding(toLength: 58, withPad: " ", startingAt: 0),
                  disabled ? "disabled " : "automatic",
                  "origin", before.0, "->", origin(h), "| top", before.1, "->", topRow(h, kind: kind, tall: tall))
        }
    }
    let above = Array(-5..<0) + Array(0..<40)
    run("1 lazy, none, wheel to row 10, insert 5 above", prepare: .scrollTo(200), rows: above)
    run("1p lazy, none, proxy row 10 top, insert 5 above", prepare: .proxyTop(10), rows: above)
    run("2 lazy, none, row 10, remove rows 0-4", prepare: .scrollTo(200), rows: Array(5..<40))
    run("3 lazy, none, row 10, row 3 grows 20->60", prepare: .scrollTo(200), tall: [3])
    run("4 lazy, none, at top (0), insert 5 above", prepare: .stay, rows: above)
    run("5 lazy, none, row 10 +10 (210), insert 5 above", prepare: .scrollTo(210), rows: above)
    run("6 lazy, none, row 10, insert 5 below viewport", prepare: .scrollTo(200),
        rows: Array(0..<30) + Array(100..<105) + Array(30..<40))
    run("7 lazy, none, row 10, insert 2 inside viewport", prepare: .scrollTo(200),
        rows: Array(0..<13) + [100, 101] + Array(13..<40))
    run("8 lazy, none, row 10, remove row 10 (the top row)", prepare: .scrollTo(200),
        rows: Array(0..<10) + Array(11..<40))
    run("9 lazy, none, row 10, replace all ids (100..<140)", prepare: .scrollTo(200),
        rows: Array(100..<140))
    run("10 eager, none, row 10, insert 5 above", kind: .eager, prepare: .scrollTo(200), rows: above)
    run("11 eager, none, row 10, remove rows 0-4", kind: .eager, prepare: .scrollTo(200), rows: Array(5..<40))
    run("12 eager, none, at top, insert 5 above", kind: .eager, prepare: .stay, rows: above)
    run("13 list, none, wheel down 200, insert 5 above", kind: .list, prepare: .scrollTo(200), rows: above)
    run("14 list, none, at top, insert 5 above", kind: .list, prepare: .stay, rows: above)
    run("15 list, none, wheel down 200, remove rows 0-4", kind: .list, prepare: .scrollTo(200), rows: Array(5..<40))
    run("16 lazy, .top, row 10, insert 5 above", anchor: .top, prepare: .scrollTo(200), rows: above)
    run("17 lazy, .top sizeChanges, row 10, insert 5 above", anchor: .topSizeChanges, prepare: .scrollTo(200), rows: above)
    run("18 lazy, .top, at top, insert 5 above", anchor: .top, prepare: .stay, rows: above)
    run("19 lazy, .top sizeChanges, at top, insert 5 above", anchor: .topSizeChanges, prepare: .stay, rows: above)
    run("20 lazy, .bottom, row 10 (mid), insert 5 above", anchor: .bottom, prepare: .scrollTo(200), rows: above)
    run("21 lazy, .bottom sizeChanges, row 10, insert 5 above", anchor: .bottomSizeChanges, prepare: .scrollTo(200), rows: above)
    run("22 lazy, .center, row 10, insert 5 above", anchor: .center, prepare: .scrollTo(200), rows: above)
    run("23 lazy, .center sizeChanges, row 10, insert 5 above", anchor: .centerSizeChanges, prepare: .scrollTo(200), rows: above)
    run("24 eager, .top sizeChanges, row 10, insert 5 above", kind: .eager, anchor: .topSizeChanges, prepare: .scrollTo(200), rows: above)
    run("25 list, .top sizeChanges, wheel 200, insert 5 above", kind: .list, anchor: .topSizeChanges, prepare: .scrollTo(200), rows: above)
}
