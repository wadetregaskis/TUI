// What a macOS search field shows at its trailing end, empty and with text,
// and what its cancel button and Escape do to the text. SwiftUI's .searchable
// on macOS is an NSSearchField in the toolbar, so the field is probed directly.
// The renders are saved as empty.png and text.png in the directory given, and
// read by eye: the field's own border swamps any pixel count of the corner.
//
//   swiftc -O searchclear.swift -o /tmp/searchclear && /tmp/searchclear /tmp
import AppKit

/// Writes the field's render to `path`, scaled up, for looking at.
@MainActor
func save(_ field: NSSearchField, _ path: String?) {
    guard let path, let rep = field.bitmapImageRepForCachingDisplay(in: field.bounds) else { return }
    field.cacheDisplay(in: field.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

@MainActor
func run() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSSearchField(frame: NSRect(x: 10, y: 15, width: 260, height: 24))
    window.contentView?.addSubview(field)
    let cell = field.cell as? NSSearchFieldCell
    print("cancel button cell present:", cell?.cancelButtonCell != nil)
    print("cancel button rect (empty):", cell.map { NSStringFromRect($0.cancelButtonRect(forBounds: field.bounds)) } ?? "-")
    field.stringValue = ""
    save(field, CommandLine.arguments.count > 1 ? CommandLine.arguments[1] + "/empty.png" : nil)
    field.stringValue = "abc"
    save(field, CommandLine.arguments.count > 1 ? CommandLine.arguments[1] + "/text.png" : nil)
    // The cancel button's action, as a click on it sends it.
    if let cancel = cell?.cancelButtonCell, let action = cancel.action {
        NSApp.sendAction(action, to: cancel.target, from: cancel)
    }
    print("text after the cancel button's action:", "\"\(field.stringValue)\"")
    // Escape in the field: the field editor's cancelOperation.
    window.makeKeyAndOrderFront(nil)
    field.stringValue = "abc"
    window.makeFirstResponder(field)
    if let editor = field.currentEditor() {
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    }
    print("text after Escape (cancelOperation):", "\"\(field.stringValue)\"")
}

MainActor.assumeIsolated { run() }
