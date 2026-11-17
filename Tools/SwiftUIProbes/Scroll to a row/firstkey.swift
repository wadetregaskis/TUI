import AppKit
import SwiftUI

// What the first key does in a focused `List` or `Table` with NOTHING selected
// (lane FIRSTKEY, 2026-11-16, after `selrow.swift` found Down selects row 0):
// Down, Up, Home, End, Page Down, Page Up and a typed `c` or `a`, each the first
// key in a fresh window. Rows 0 to 99 named "<letter>-<index>", the letter
// cycling a to z, so `c` names rows 2, 28, 54 and 80, and `a` rows 0, 26, 52
// and 78; 24 points tall in a 300 x 320 window, the table view the first
// responder. Then the same keys with row 5
// selected (do Home, End and the page keys move a selection at all?), with
// row 5 selected and then cleared by the app (does the table view remember
// where it was?), and with nothing selected after the wheel's way of moving,
// a scroll to row 50 (`scrollTo`, which `selrow.swift` showed moves only the
// rows in view). For a `List` and a `Table`, a single selection (`Int?`) and a
// multiple one (`Set<Int>`). Keys take AppKit's route as `selrow.swift` sends
// them.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 firstkey.swift -o "$TMPDIR/firstkey"
//   "$TMPDIR/firstkey"

let letters = Array("abcdefghijklmnopqrstuvwxyz")
struct Item: Identifiable { let id: Int; var name: String { "\(letters[id % 26])-\(id)" } }
let items = (0..<100).map(Item.init)

@MainActor final class Model: ObservableObject {
    @Published var one: Int?
    @Published var many: Set<Int> = []
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

struct Key {
    let name: String
    let characters: String
    let code: UInt16
    let flags: NSEvent.ModifierFlags
    init(_ name: String, _ scalar: Int, _ code: UInt16, function: Bool = true) {
        self.name = name
        characters = String(UnicodeScalar(scalar)!)
        self.code = code
        flags = function ? [.function] : []
    }
}

let keys = [
    Key("Down", NSDownArrowFunctionKey, 125), Key("Up", NSUpArrowFunctionKey, 126),
    Key("Home", NSHomeFunctionKey, 115), Key("End", NSEndFunctionKey, 119),
    Key("Page Down", NSPageDownFunctionKey, 121), Key("Page Up", NSPageUpFunctionKey, 116),
    Key("c", 0x63, 8, function: false), Key("a", 0x61, 0, function: false),
]

@MainActor func post(_ key: Key, window: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: key.flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: key.characters,
            charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.code)!
        if window.isKeyWindow {
            NSApp.postEvent(event, atStart: false)
        } else {
            if type == .keyDown, window.performKeyEquivalent(with: event) { continue }
            window.sendEvent(event)
        }
    }
    spin()
}

enum Start: String, CaseIterable {
    case empty = "nothing selected"
    case five = "row 5 selected"
    case cleared = "row 5 selected, then cleared by the app"
    case scrolled = "nothing selected, scrolled to row 50"
}

@MainActor func run(_ kind: Kind, multiple: Bool, start: Start, key: Key) {
    let m = Model()
    if start == .five || start == .cleared { m.one = 5; m.many = [5] }
    let window = KeyWindow(
        contentRect: NSRect(x: 200, y: 300, width: 300, height: 320), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: Probe(kind: kind, multiple: multiple, m: m))
    window.makeKeyAndOrderFront(nil)
    spin(0.6)
    guard let table = find(NSTableView.self, in: window.contentView!) else { print(kind, "no table"); return }
    window.makeFirstResponder(table)
    spin()
    if start == .cleared { m.one = nil; m.many = []; spin() }
    if start == .scrolled { m.proxy?.scrollTo(50, anchor: .top); spin(0.6) }
    func state() -> String {
        let selection = multiple ? "\(m.many.sorted())" : (m.one.map(String.init) ?? "nil")
        let shown = table.rows(in: table.visibleRect)
        let rows = shown.length > 0 ? "\(shown.location)...\(shown.location + shown.length - 1)" : "none"
        return "selection \(selection), selected row \(table.selectedRow), rows \(rows)"
    }
    let before = state()
    post(key, window: window)
    print("  \(key.name): \(before) -> \(state())")
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
                    for start in Start.allCases {
                        print("\(kind.rawValue), \(multiple ? "Set<Int>" : "Int?"), \(start.rawValue):")
                        for key in keys { run(kind, multiple: multiple, start: start, key: key) }
                    }
                }
            }
        }
    }
}
