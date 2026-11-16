import AppKit
import SwiftUI

// Whether `ScrollViewProxy.scrollTo(_:anchor:)` on a row of a `List` or a
// `Table` with a selection moves the selection or the keyboard's row (G6, from
// building the tuitree editor, 2026-11-16). Rows 0 to 99, 24 points tall, in a
// 300 x 320 window, the table view the first responder, the selection row 0
// (or nil). The app calls `scrollTo(50)` with no anchor and with `.top`; after
// it, the selection binding, the table view's selected row and the rows in
// view; then Down goes through AppKit's route as `sections.swift` in
// `Bug-hunt parity items (1116B)` sends it, and the same again: does Down go
// on from row 0 (and scroll back) or from row 50? Run for a `List` and a
// `Table`, a single selection (`Int?`) and a multiple one (`Set<Int>`).
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 selrow.swift -o "$TMPDIR/selrow"
//   "$TMPDIR/selrow"

struct Item: Identifiable { let id: Int; var name: String { "Row \(id)" } }
let items = (0..<100).map(Item.init)

@MainActor final class Model: ObservableObject {
    @Published var one: Int? = 0
    @Published var many: Set<Int> = [0]
    var proxy: ScrollViewProxy?
}

enum Kind: String, CaseIterable { case list = "List", table = "Table" }

struct Probe: View {
    let kind: Kind
    let multiple: Bool
    @ObservedObject var m: Model
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                switch (kind, multiple) {
                case (.list, false):
                    List(items, selection: $m.one) { Text($0.name).frame(height: 24) }
                case (.list, true):
                    List(items, selection: $m.many) { Text($0.name).frame(height: 24) }
                case (.table, false):
                    Table(items, selection: $m.one) { TableColumn("Name", value: \.name) }
                case (.table, true):
                    Table(items, selection: $m.many) { TableColumn("Name", value: \.name) }
                }
            }
            .onAppear { m.proxy = proxy }
        }
    }
}

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews { if let match = find(type, in: sub) { return match } }
    return nil
}

@MainActor func post(_ characters: String, keyCode: UInt16, window: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        if window.isKeyWindow {
            NSApp.postEvent(event, atStart: false)
        } else {
            if type == .keyDown, window.performKeyEquivalent(with: event) { continue }
            window.sendEvent(event)
        }
    }
    spin()
}

let down = (String(UnicodeScalar(NSDownArrowFunctionKey)!), UInt16(125))

@MainActor func run(_ kind: Kind, multiple: Bool, anchor: UnitPoint?, startNil: Bool) {
    let m = Model()
    if startNil { m.one = nil; m.many = [] }
    let window = KeyWindow(
        contentRect: NSRect(x: 200, y: 300, width: 300, height: 320), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: Probe(kind: kind, multiple: multiple, m: m))
    window.makeKeyAndOrderFront(nil)
    spin(0.6)
    guard let table = find(NSTableView.self, in: window.contentView!) else { print(kind, "no table"); return }
    window.makeFirstResponder(table)
    spin()
    func state(_ step: String) {
        let selection = multiple ? "\(m.many.sorted())" : (m.one.map(String.init) ?? "nil")
        let shown = table.rows(in: table.visibleRect)
        let rows = shown.length > 0 ? "\(shown.location)...\(shown.location + shown.length - 1)" : "none"
        print("  \(step): selection \(selection), selected row \(table.selectedRow), rows \(rows) in view")
    }
    let anchorName = anchor.map { $0 == .top ? ".top" : "\($0)" } ?? "no anchor"
    print("\(kind.rawValue), \(multiple ? "Set<Int>" : "Int?"), selection \(startNil ? "empty" : "row 0"), "
        + "scrollTo(50, \(anchorName)): first responder \(type(of: window.firstResponder!))")
    state("start")
    if let anchor { m.proxy?.scrollTo(50, anchor: anchor) } else { m.proxy?.scrollTo(50) }
    spin(0.6)
    state("scrollTo(50)")
    post(down.0, keyCode: down.1, window: window); state("Down")
    post(down.0, keyCode: down.1, window: window); state("Down")
    window.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            NSApp.activate(ignoringOtherApps: true)
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            for kind in Kind.allCases {
                for multiple in [false, true] {
                    run(kind, multiple: multiple, anchor: nil, startNil: false)
                    run(kind, multiple: multiple, anchor: .top, startNil: false)
                    run(kind, multiple: multiple, anchor: nil, startNil: true)
                }
            }
        }
    }
}
