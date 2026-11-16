import AppKit
import SwiftUI

// What `.scrollPosition(id:)` with NO anchor does when the app writes the id
// (bug hunt 1116B, 2026-11-16). Rows 0..<100, 20 points tall, in a 200-point
// viewport (ten rows), in a `LazyVStack` and a `VStack` marked
// `.scrollTargetLayout()`, and in a `List`; the lazy stack again with
// `anchor: .top` to compare. Each step prints the clip view's y origin, the
// row at the viewport's top (origin / 20 for a stack; the first visible row
// of the List's table view), the bound id, and every write the binding saw.
//
//   1. appear with the id nil: does SwiftUI write the top row's id?
//   2. the app writes 50: where does row 50 land, what does the id read?
//   3. the app writes 50 again (no change)
//   4. the user scrolls to the top (live-scroll notifications, as
//      `Nested scroll position/nested.swift` posts them): the id?
//   5. the app writes 50 again: does the view move?
//   6. the user scrolls to y 1600 (row 80 at the top), then the app writes 50:
//      where does it land coming from below?
//   7. the app writes 52, already in view: does the view move?
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 scrollid.swift -o "$TMPDIR/scrollid"
//   "$TMPDIR/scrollid"

@MainActor var keep: [NSWindow] = []

@Observable final class Model {
    var id: Int? = nil { didSet { writes.append(id.map(String.init) ?? "nil") } }
    @ObservationIgnored var writes: [String] = []
}

enum Kind: String, CaseIterable { case lazy, eager, list, lazyTop = "lazy, anchor .top" }

struct Probe: View {
    let kind: Kind
    @Bindable var m: Model
    var body: some View {
        switch kind {
        case .lazy:
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Text("r\($0)").frame(height: 20) } }
                    .scrollTargetLayout()
            }
            .scrollPosition(id: $m.id)
        case .lazyTop:
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Text("r\($0)").frame(height: 20) } }
                    .scrollTargetLayout()
            }
            .scrollPosition(id: $m.id, anchor: .top)
        case .eager:
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<100, id: \.self) { Text("r\($0)").frame(height: 20) } }
                    .scrollTargetLayout()
            }
            .scrollPosition(id: $m.id)
        case .list:
            List(0..<100, id: \.self) { Text("r\($0)") }
                .scrollPosition(id: $m.id)
        }
    }
}

@MainActor func spin(_ s: Double = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews { if let match = find(type, in: sub) { return match } }
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

@MainActor func run(_ kind: Kind) {
    let m = Model()
    let size = CGSize(width: 200, height: 200)
    let h = NSHostingView(rootView: Probe(kind: kind, m: m))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    guard let sv = find(NSScrollView.self, in: h) else { print(kind.rawValue, "no scroll view"); return }
    let table = find(NSTableView.self, in: h)
    func state(_ step: String) {
        let y = sv.contentView.bounds.origin.y
        let top: Int
        if let table {
            let rows = table.rows(in: sv.contentView.documentVisibleRect)
            top = rows.location
        } else {
            top = Int(y / 20)
        }
        print("  \(step): y \(Int(y)), top row \(top), id \(m.id.map(String.init) ?? "nil"), writes \(m.writes)")
        m.writes = []
    }
    print("\(kind.rawValue)\(table.map { " (row height \(Int($0.rect(ofRow: 0).height)))" } ?? ""):")
    state("1 appear, id nil")
    m.id = 50; m.writes = []; spin()
    state("2 app writes 50")
    m.id = 50; m.writes = []; spin()
    state("3 app writes 50 again")
    liveScroll(sv, to: 0)
    state("4 user scrolls to the top")
    m.id = 50; m.writes = []; spin()
    state("5 app writes 50")
    liveScroll(sv, to: 1600)
    state("6a user scrolls to y 1600")
    m.id = 50; m.writes = []; spin()
    state("6b app writes 50")
    m.id = 52; m.writes = []; spin()
    state("7 app writes 52")
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            print("(writes: what the binding was set to during the step, the app's own write left out)")
            for kind in Kind.allCases { run(kind) }
        }
    }
}
