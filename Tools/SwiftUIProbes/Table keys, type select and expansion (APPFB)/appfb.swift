import AppKit
import SwiftUI

// APPFB (app feedback from tuitop, 2026-11-14): what does a focused SwiftUI
// `Table` on macOS do with the keys an app's commands also want, and how do
// its tree rows start?
//
// 1. Down in a single-selection table: does the selection move?
// 2. A bare `k` with a `Button(...).keyboardShortcut("k", modifiers: [])`
//    outside the table: does the button fire, or does type select take it?
// 3. A bare `t` with `.onKeyPress("t")` on the table: does the handler run
//    ahead of type select?
// 4. A bare `z` with no binding: type select (selects "zulu")?
// 5. `Table(_:children:)`: how many rows show at first (every branch closed?)
// 6. `DisclosureTableRow(_:isExpanded:)` bound to `true` at first, recursing
//    through a custom `TableRowContent` over a tree of any depth: how many rows?
//
// Keys are posted to the app's own queue (`NSApp.postEvent`, as
// `Menu keyboard walk (1110E)/walk.swift` does), so they take AppKit's whole
// route: key equivalents first, then the first responder.
//
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 appfb.swift -o "$TMPDIR/appfb" && "$TMPDIR/appfb"

struct Row: Identifiable, Hashable {
    let id: String
    var name: String { id }
    var children: [Row]?
}

let flat = ["alpha", "bravo", "kilo", "tango", "zulu"].map { Row(id: $0) }
let tree = [
    Row(id: "root", children: [
        Row(id: "a", children: [Row(id: "a1"), Row(id: "a2", children: [Row(id: "a2x")])]),
        Row(id: "b"),
    ]),
    Row(id: "other", children: [Row(id: "o1")]),
]

@MainActor final class Log {
    static var lines: [String] = []
    static func add(_ line: String) { lines.append(line) }
}

@MainActor final class Model: ObservableObject {
    @Published var selection: String? = "alpha"
}

struct FlatTable: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack {
            Button("Kill") { Log.add("button k FIRED") }
                .keyboardShortcut("k", modifiers: [])
            Table(flat, selection: $model.selection) { TableColumn("Name", value: \.name) }
                .onKeyPress("t") {
                    Log.add("onKeyPress t RAN")
                    return .handled
                }
        }
    }
}

/// A tree of any depth, each branch bound open at first.
struct OpenRows: TableRowContent {
    let rows: [Row]
    var tableRowBody: some TableRowContent<Row> {
        ForEach(rows) { row in
            if let children = row.children {
                DisclosureTableRow(row, isExpanded: .constant(true)) { OpenRows(rows: children) }
            } else {
                TableRow(row)
            }
        }
    }
}

struct ChildrenTable: View {
    var body: some View {
        Table(tree, children: \.children) { TableColumn("Name", value: \.name) }
    }
}

struct BoundTable: View {
    var body: some View {
        Table(of: Row.self) { TableColumn("Name", value: \.name) } rows: { OpenRows(rows: tree) }
    }
}

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews { if let match = find(type, in: sub) { return match } }
    return nil
}

/// Each row's depth in the outline, top to bottom (SwiftUI draws the names
/// itself, with no text field to read): "0 1 1 0" is a root, two children and
/// a root.
@MainActor func names(_ table: NSTableView) -> String {
    guard let outline = table as? NSOutlineView else { return "not an outline" }
    return "depths " + (0..<table.numberOfRows).map { String(outline.level(forRow: $0)) }.joined(separator: " ")
}

@MainActor func post(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = [], window: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        if window.isKeyWindow {
            NSApp.postEvent(event, atStart: false)
        } else {
            // A process started from a shell in the background is not let take
            // the key window, so AppKit's route for a key in the key window is
            // taken by hand: key equivalents down the window's views, then the
            // main menu's, then the first responder's keyDown.
            if type == .keyDown, window.performKeyEquivalent(with: event) || NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                Log.add("(taken as a key equivalent)")
                continue
            }
            window.sendEvent(event)
        }
    }
    spin(1.2)  // longer than type select's pause, so each letter starts afresh
}

@MainActor func window<V: View>(_ view: V) -> KeyWindow {
    let window = KeyWindow(
        contentRect: NSRect(x: 200, y: 300, width: 360, height: 320), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    window.makeKey()
    spin(0.6)
    return window
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

            let model = Model()
            let flatWindow = window(FlatTable(model: model))
            if let table = find(NSTableView.self, in: flatWindow.contentView!) {
                flatWindow.makeFirstResponder(table)
            }
            spin()
            @MainActor func report(_ step: String) {
                let fired = Log.lines.isEmpty ? "" : " [" + Log.lines.joined(separator: ", ") + "]"
                Log.lines = []
                print("\(step): selection \(model.selection ?? "none")\(fired)")
            }
            print("key window: \(flatWindow.isKeyWindow), first responder: \(type(of: flatWindow.firstResponder!))")
            report("start")
            post(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, flags: [.numericPad, .function], window: flatWindow)
            report("down")
            post("k", keyCode: 40, window: flatWindow)
            report("k (button has .keyboardShortcut(\"k\", modifiers: []))")
            post("t", keyCode: 17, window: flatWindow)
            report("t (table has .onKeyPress(\"t\"))")
            post("z", keyCode: 6, window: flatWindow)
            report("z (no binding)")
            flatWindow.orderOut(nil)

            let childrenWindow = window(ChildrenTable())
            spin(1)
            let childrenTable = find(NSTableView.self, in: childrenWindow.contentView!)!
            print("Table(_:children:) rows at first: \(childrenTable.numberOfRows) of 8: \(names(childrenTable))")
            childrenWindow.orderOut(nil)

            let boundWindow = window(BoundTable())
            spin(1)
            let boundTable = find(NSTableView.self, in: boundWindow.contentView!)!
            print("recursive DisclosureTableRow(isExpanded: true) rows at first: \(boundTable.numberOfRows) of 8: \(names(boundTable))")
            spin(2)
            print("... two seconds later: \(boundTable.numberOfRows) of 8: \(names(boundTable))")
            exit(0)
        }
    }
}
