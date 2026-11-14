import SwiftUI
import AppKit

// Does a `.scrollPosition` binding whose VALUE changes scroll the view, when
// no `scrollTo` was called (lane SCROLL-FIT bench, 2026-11-14)? Four ways to
// hand a scroll view a new position, each ticked through rows 0, 40, 80, 40:
//   constant  `.scrollPosition(.constant(ScrollPosition(y: line)))`, `line`
//             @State, so the body builds a new position every update
//   getter    `Binding(get: { ScrollPosition(y: line) }, set: { _ in })`
//   assign    `@State var pos`, ticked with `pos = ScrollPosition(y: line)`
//   scrollTo  `@State var pos`, ticked with `pos.scrollTo(y: line)`
// Then, for `constant` and `scrollTo`: the user scrolls away (a live scroll),
// and the SAME value is handed over again (body re-run with the same `line`;
// `scrollTo(y:)` of the same offset). Also prints whether two
// `ScrollPosition(y: 40)` compare equal. Prints the clip view's y origin.

@MainActor var keep: [NSWindow] = []

enum Mode: String { case constant, getter, assign, scrollTo }

@Observable final class Model {
    var line: CGFloat = 0
    var pos = ScrollPosition(y: 0)
    var bump = 0
}

struct Probe: View {
    let mode: Mode
    @Bindable var m: Model
    var body: some View {
        let _ = m.bump
        let rows = ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { i in Text("r\(i)").frame(height: 1) }
            }
        }
        .scrollIndicators(.never)
        .frame(width: 100, height: 20)
        switch mode {
        case .constant: rows.scrollPosition(.constant(ScrollPosition(y: m.line)))
        case .getter: rows.scrollPosition(Binding(get: { ScrollPosition(y: m.line) }, set: { _ in }))
        case .assign, .scrollTo: rows.scrollPosition($m.pos)
        }
    }
}

@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func findScroll(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for c in v.subviews { if let s = findScroll(c) { return s } }
    return nil
}
@MainActor func liveScroll(_ sv: NSScrollView, to y: CGFloat) {
    let nc = NotificationCenter.default
    nc.post(name: NSScrollView.willStartLiveScrollNotification, object: sv)
    spin(0.05)
    sv.contentView.scroll(to: NSPoint(x: 0, y: y))
    sv.reflectScrolledClipView(sv.contentView)
    nc.post(name: NSScrollView.didLiveScrollNotification, object: sv)
    spin(0.05)
    nc.post(name: NSScrollView.didEndLiveScrollNotification, object: sv)
    spin()
}

@MainActor func run(_ mode: Mode) {
    let m = Model()
    let size = CGSize(width: 100, height: 20)
    let h = NSHostingView(rootView: Probe(mode: mode, m: m))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    guard let sv = findScroll(h) else { print(mode.rawValue, "no scroll view"); return }
    func y() -> Int { Int(sv.contentView.bounds.origin.y) }
    var line = "\(mode.rawValue):"
    line += " start=\(y())"
    for target in [40, 80, 40] as [CGFloat] {
        switch mode {
        case .constant, .getter: m.line = target
        case .assign: m.pos = ScrollPosition(y: target)
        case .scrollTo: m.pos.scrollTo(y: target)
        }
        spin()
        line += " ->\(Int(target))=\(y())"
    }
    liveScroll(sv, to: 10)
    line += " user->10=\(y())"
    switch mode {
    case .constant, .getter: m.bump += 1  // body again, same `line`
    case .assign: m.pos = ScrollPosition(y: 40)
    case .scrollTo: m.pos.scrollTo(y: 40)
    }
    spin()
    line += " same40=\(y())"
    print(line)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            print("ScrollPosition(y: 40) == ScrollPosition(y: 40):", ScrollPosition(y: 40) == ScrollPosition(y: 40))
            var a = ScrollPosition(y: 40); let b = a; a.scrollTo(y: 40)
            print("after scrollTo(y: 40) of a copy, equal:", a == b)
            for mode in [Mode.constant, .getter, .assign, .scrollTo] { run(mode) }
        }
    }
}
