import AppKit
import SwiftUI

// LAZY-SECTION (lane 2026-11-17): does `.focusSection()` change where Tab and
// Shift-Tab go in a `LazyVStack` in a `ScrollView`, against a `VStack`?
//
// The harness of "Tab into rows off screen (1110F)": rows of text fields in a
// 300 × 200 point key window, Tab (or Shift-Tab) key events sent through the
// window one at a time (`NSWindow.sendEvent`), the focused field's text and
// the scroll view's clip origin printed after each. Text fields, because Tab
// reaches them without Full Keyboard Access.
//
// - rows: each row `.focusSection()`;
// - stack: the stack `.focusSection()`, under a section of two fields
//   ("side 0", "side 1") outside the scroll view;
// each lazy and eager, Tab from the first row, then Shift-Tab from the first
// row.
//
//   swiftc -parse-as-library sections.swift -o /tmp/sections && /tmp/sections

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

@MainActor func tab(_ window: NSWindow, shift: Bool) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: shift ? "\u{19}" : "\t",
            charactersIgnoringModifiers: shift ? "\u{19}" : "\t", isARepeat: false, keyCode: 48)!
        window.sendEvent(event)
    }
}

struct Field: View {
    @State var text: String
    init(_ text: String) { _text = State(initialValue: text) }
    var body: some View { TextField("", text: $text) }
}

struct Rows: View {
    let lazy: Bool
    let rowSections: Bool
    var body: some View {
        if lazy {
            LazyVStack { ForEach(0..<60, id: \.self) { row($0) } }
        } else {
            VStack { ForEach(0..<60, id: \.self) { row($0) } }
        }
    }
    @ViewBuilder func row(_ index: Int) -> some View {
        if rowSections { Field("row \(index)").focusSection() } else { Field("row \(index)") }
    }
}

struct Page: View {
    let lazy: Bool
    let stackSection: Bool
    var body: some View {
        if stackSection {
            VStack {
                HStack { Field("side 0"); Field("side 1") }.focusSection()
                ScrollView { Rows(lazy: lazy, rowSections: false).focusSection() }
            }
        } else {
            ScrollView { Rows(lazy: lazy, rowSections: true) }
        }
    }
}

@MainActor func run(_ name: String, tabs: Int, shift: Bool, _ view: Page) {
    let size = NSSize(width: 300, height: 200)
    let window = KeyWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 300), size: size),
                           styleMask: [.titled], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    spin(0.5)
    let made = fields(hosting).filter { $0.stringValue.hasPrefix("row") }.count
    if let first = fields(hosting).first(where: { $0.stringValue == "row 0" }) {
        window.makeFirstResponder(first)
    }
    spin()
    var log = ["start: \(focusedRow(window)) \(origin(hosting))"]
    for step in 1...tabs {
        tab(window, shift: shift)
        spin()
        log.append("\(shift ? "shift-tab" : "tab") \(step): \(focusedRow(window)) \(origin(hosting))")
    }
    print("\(name) (60 rows, \(made) row fields made at first)")
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
            for (label, stackSection) in [("row sections", false), ("stack section", true)] {
                for lazy in [true, false] {
                    let name = "\(lazy ? "lazy" : "eager"), \(label)"
                    run(name + ", Tab", tabs: 12, shift: false, Page(lazy: lazy, stackSection: stackSection))
                    run(name + ", Shift-Tab", tabs: 4, shift: true, Page(lazy: lazy, stackSection: stackSection))
                }
            }
            exit(0)
        }
    }
}
