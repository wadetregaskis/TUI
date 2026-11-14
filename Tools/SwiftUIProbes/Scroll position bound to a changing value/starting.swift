import SwiftUI
import AppKit

// Does the FIRST value of a `.scrollPosition` binding place the scroll view
// as it appears (lane SCROLL-FIT follow-up, 2026-11-14)? Each way of handing
// over a position, starting at a non-zero one, in an eager VStack and a
// LazyVStack of 200 one-point rows in a 20-point viewport:
//   constant  `.scrollPosition(.constant(ScrollPosition(y: 10)))`
//   state     `@State var pos = ScrollPosition(y: 10)`, bound
//   scrolled  `@State var pos = ScrollPosition()` then `pos.scrollTo(y: 10)`
//             before the view appears (same value as `state` but a request
//             made by the method)
//   id        `@State var pos = ScrollPosition(id: 30)`, rows `.id(i)`
//   target    the same, the stack marked `.scrollTargetLayout()` (which a
//             position by id reads its rows from)
//   bottom    `@State var pos = ScrollPosition(edge: .bottom)`
//   past      `@State var pos = ScrollPosition(y: 500)`, past the end
//             (content 200, viewport 20)
// and the held positions again on a `List` of the same 200 rows, which is
// then handed `ScrollPosition(y: 40)` and `scrollTo(id: 100)` to see whether
// it follows the binding at all. Prints the clip view's y origin once the
// view is up, and what the binding then holds.

@MainActor var keep: [NSWindow] = []

enum Mode: String, CaseIterable { case constant, state, scrolled, id, target, bottom, past }

@Observable final class Model {
    var pos: ScrollPosition
    init(_ pos: ScrollPosition) { self.pos = pos }
}

struct Rows: View {
    let lazy: Bool
    let targets: Bool
    var body: some View {
        if lazy {
            LazyVStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { i in Text("r\(i)").frame(height: 1).id(i) }
            }
            .scrollTargetLayout(isEnabled: targets)
        } else {
            VStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { i in Text("r\(i)").frame(height: 1).id(i) }
            }
            .scrollTargetLayout(isEnabled: targets)
        }
    }
}

struct Probe: View {
    let mode: Mode
    let lazy: Bool
    let inList: Bool
    @Bindable var m: Model
    var body: some View {
        if inList {
            List(0..<200, id: \.self) { i in Text("r\(i)").id(i) }
                .scrollIndicators(.never)
                .frame(width: 100, height: 20)
                .scrollPosition($m.pos)
        } else {
            scrolled
        }
    }
    @ViewBuilder var scrolled: some View {
        let rows = ScrollView { Rows(lazy: lazy, targets: mode == .target) }
            .scrollIndicators(.never)
            .frame(width: 100, height: 20)
        if mode == .constant {
            rows.scrollPosition(.constant(ScrollPosition(y: 10)))
        } else {
            rows.scrollPosition($m.pos)
        }
    }
}

@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}

@MainActor func run(_ mode: Mode, lazy: Bool, inList: Bool = false) {
    let start: ScrollPosition
    switch mode {
    case .constant, .state: start = ScrollPosition(y: 10)
    case .scrolled:
        var p = ScrollPosition()
        p.scrollTo(y: 10)
        start = p
    case .id, .target: start = ScrollPosition(id: 30)
    case .bottom: start = ScrollPosition(edge: .bottom)
    case .past: start = ScrollPosition(y: 500)
    }
    let m = Model(start)
    let size = CGSize(width: 100, height: 20)
    let h = NSHostingView(rootView: Probe(mode: mode, lazy: lazy, inList: inList, m: m))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    guard let sv = findScroll(h) else { print(mode.rawValue, "no scroll view"); return }
    let y = Int(sv.contentView.bounds.origin.y)
    let held = mode == .constant ? "-" : "point=\(m.pos.point.map { "\(Int($0.y))" } ?? "nil") "
        + "id=\(m.pos.viewID.map { "\($0)" } ?? "nil") edge=\(m.pos.edge.map { "\($0)" } ?? "nil") "
        + "byUser=\(m.pos.isPositionedByUser)"
    var later = ""
    if inList, mode == .state {
        // Whether the list follows the binding at all: a new value once it is up.
        m.pos = ScrollPosition(y: 40)
        spin()
        later = "  then y: 40 -> \(Int(sv.contentView.bounds.origin.y))"
        m.pos.scrollTo(id: 100)
        spin()
        later += ", scrollTo(id: 100) -> \(Int(sv.contentView.bounds.origin.y))"
    }
    print("\(inList ? "list " : lazy ? "lazy " : "eager") \(mode.rawValue): start=\(y)  binding: \(held)\(later)")
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            for lazy in [false, true] {
                for mode in Mode.allCases { run(mode, lazy: lazy) }
            }
            for mode in [Mode.state, .scrolled, .id, .bottom, .past] { run(mode, lazy: true, inList: true) }
        }
    }
}
