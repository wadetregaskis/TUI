import AppKit
import SwiftUI

// Where the keyboard starts in a `List` with `Section` headers, and whether a
// header can ever be the keyboard row (bug hunt 1116B, 2026-11-16). Two
// sections, "Fruit" (apple, banana, cherry) and "Veg" (daikon, endive), in a
// `List(selection:)`, its table view the first responder, the selection nil.
// Keys go through AppKit's route as `Table keys, type select and expansion
// (APPFB)/appfb.swift` sends them; after each, the selection, the table
// view's selected row. Run for
// the default list style, `.sidebar`, `.inset` and `.plain`, and for a single
// selection (`Int?`) and a multiple one (`Set<Int>`). The table view has a
// row for each header too, in order: row 0 is "Fruit" and row 4 "Veg".
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 sections.swift -o "$TMPDIR/sections"
//   "$TMPDIR/sections"

let names = ["apple", "banana", "cherry", "daikon", "endive"]

@MainActor final class Model: ObservableObject {
    @Published var one: Int?
    @Published var many: Set<Int> = []
}

enum Style: String, CaseIterable { case automatic, sidebar, inset, plain }

struct Rows: View {
    var body: some View {
        Section("Fruit") { ForEach(0..<3, id: \.self) { Text(names[$0]) } }
        Section("Veg") { ForEach(3..<5, id: \.self) { Text(names[$0]) } }
    }
}

struct Probe: View {
    let style: Style
    let multiple: Bool
    @ObservedObject var m: Model
    var body: some View {
        let list = Group {
            if multiple { List(selection: $m.many) { Rows() } } else { List(selection: $m.one) { Rows() } }
        }
        switch style {
        case .automatic: list
        case .sidebar: list.listStyle(.sidebar)
        case .inset: list.listStyle(.inset)
        case .plain: list.listStyle(.plain)
        }
    }
}

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
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
    spin(0.4)
}

let down = (String(UnicodeScalar(NSDownArrowFunctionKey)!), UInt16(125))
let up = (String(UnicodeScalar(NSUpArrowFunctionKey)!), UInt16(126))
let home = (String(UnicodeScalar(NSHomeFunctionKey)!), UInt16(115))
let end = (String(UnicodeScalar(NSEndFunctionKey)!), UInt16(119))

@MainActor func run(_ style: Style, multiple: Bool) {
    let m = Model()
    let window = KeyWindow(
        contentRect: NSRect(x: 200, y: 300, width: 300, height: 320), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: Probe(style: style, multiple: multiple, m: m))
    window.makeKeyAndOrderFront(nil)
    spin(0.6)
    guard let table = find(NSTableView.self, in: window.contentView!) else { print(style, "no table"); return }
    window.makeFirstResponder(table)
    spin()
    func state(_ step: String) {
        let selection = multiple
            ? "[" + m.many.sorted().map { names[$0] }.joined(separator: ",") + "]"
            : (m.one.map { names[$0] } ?? "nil")
        print("  \(step): selection \(selection), selected row \(table.selectedRow)")
    }
    print("\(style.rawValue), \(multiple ? "Set<Int>" : "Int?"): first responder \(type(of: window.firstResponder!)), \(table.numberOfRows) rows")
    state("start")
    post(down.0, keyCode: down.1, window: window); state("Down")
    post(down.0, keyCode: down.1, window: window); state("Down")
    post(down.0, keyCode: down.1, window: window); state("Down")
    post(down.0, keyCode: down.1, window: window); state("Down (past the Veg header?)")
    post(up.0, keyCode: up.1, window: window); state("Up (back across it)")
    post(end.0, keyCode: end.1, window: window); state("End")
    post(home.0, keyCode: home.1, window: window); state("Home")
    // From nothing selected, Up.
    if multiple { m.many = [] } else { m.one = nil }
    spin()
    post(up.0, keyCode: up.1, window: window); state("selection cleared, then Up")
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
            for style in Style.allCases {
                run(style, multiple: false)
                run(style, multiple: true)
            }
        }
    }
}
