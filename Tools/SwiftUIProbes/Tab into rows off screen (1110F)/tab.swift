import AppKit
import SwiftUI

// FORM-SCROLL and LAZY-TAB (hunt 2026-11-10): where does Tab go when the next
// control is below the visible area?
//
// Each case hosts rows of text fields, "row 0" to "row N", in a 300 × 200
// point key window, focuses the first field, then sends Tab key events
// through the window one at a time (`NSWindow.sendEvent`, as the keyboard
// would) and prints, after each, the row whose field holds the focus and the
// enclosing scroll view's clip origin (`none` when SwiftUI made no
// NSScrollView). Text fields, because Tab reaches them without Full Keyboard
// Access.
//
// - lazy: ScrollView { LazyVStack { ForEach rows } } — the rows past the
//   visible band have not been made yet;
// - eager: the same with a VStack, every row made;
// - grouped: Form { ForEach rows }.formStyle(.grouped);
// - columns: Form { ForEach rows }.formStyle(.columns).
//
//   swiftc -parse-as-library tab.swift -o /tmp/tab && /tmp/tab

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? {
    if let s = v as? T { return s }
    for c in v.subviews { if let s = find(c, t) { return s } }
    return nil
}

@MainActor func fields(_ v: NSView) -> [NSTextField] {
    var out: [NSTextField] = []
    if let f = v as? NSTextField, f.isEditable { out.append(f) }
    for c in v.subviews { out += fields(c) }
    return out
}

@MainActor func focusedRow(_ window: NSWindow) -> String {
    guard let responder = window.firstResponder else { return "nothing" }
    if let editor = responder as? NSTextView, editor.isFieldEditor,
       let field = editor.delegate as? NSTextField {
        return field.stringValue
    }
    if let field = responder as? NSTextField { return field.stringValue }
    return String(describing: type(of: responder))
}

@MainActor func origin(_ h: NSView) -> String {
    guard let sv = find(h, NSScrollView.self) else { return "none" }
    return "y=\(Int(sv.contentView.bounds.origin.y))"
}

@MainActor func tab(_ window: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\t",
            charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        window.sendEvent(event)
    }
}

struct Row: View {
    let index: Int
    @State var text: String
    init(_ index: Int) { self.index = index; _text = State(initialValue: "row \(index)") }
    var body: some View { TextField("", text: $text) }
}

@MainActor func run<V: View>(_ name: String, rows: Int, tabs: Int, _ view: V) {
    let size = NSSize(width: 300, height: 200)
    let window = KeyWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 300), size: size),
                           styleMask: [.titled], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    spin(0.5)
    let made = fields(hosting).count
    if let first = fields(hosting).first(where: { $0.stringValue == "row 0" }) {
        window.makeFirstResponder(first)
    }
    spin()
    var log = ["start: \(focusedRow(window)) \(origin(hosting))"]
    for step in 1...tabs {
        tab(window)
        spin()
        log.append("tab \(step): \(focusedRow(window)) \(origin(hosting))")
    }
    print("\(name) (\(rows) rows, \(made) fields made at first)")
    for line in log { print("  " + line) }
    window.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            run("lazy", rows: 60, tabs: 16,
                ScrollView { LazyVStack { ForEach(0..<60, id: \.self) { Row($0) } } })
            run("eager", rows: 60, tabs: 16,
                ScrollView { VStack { ForEach(0..<60, id: \.self) { Row($0) } } })
            run("grouped", rows: 30, tabs: 12,
                Form { ForEach(0..<30, id: \.self) { Row($0) } }.formStyle(.grouped))
            run("columns", rows: 30, tabs: 12,
                Form { ForEach(0..<30, id: \.self) { Row($0) } }.formStyle(.columns))
            exit(0)
        }
    }
}
