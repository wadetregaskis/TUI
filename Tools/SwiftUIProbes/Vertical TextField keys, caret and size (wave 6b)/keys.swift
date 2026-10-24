import SwiftUI
import AppKit

// Measures what a vertical-axis TextField does with each newline-ish key, on
// the running macOS's SwiftUI, through an NSWindow's key path.

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class Model: ObservableObject {
    @Published var text = ""
    @Published var submits = 0
    @Published var selection: TextSelection?
}

struct Probe: View {
    @ObservedObject var model: Model
    let axis: Axis?
    let submit: Bool
    var body: some View {
        Group {
            if let axis {
                if submit {
                    TextField("Title", text: $model.text, axis: axis).onSubmit { model.submits += 1 }
                } else {
                    TextField("Title", text: $model.text, axis: axis)
                }
            } else {
                TextField("Title", text: $model.text).onSubmit { model.submits += 1 }
            }
        }
        .frame(width: 200)
        .padding()
    }
}

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func findTextViews(_ v: NSView) -> [NSView] {
    var out: [NSView] = []
    if v is NSTextField || v is NSTextView { out.append(v) }
    for c in v.subviews { out += findTextViews(c) }
    return out
}

@MainActor func run(axis: Axis?, submit: Bool, label: String) {
    let model = Model()
    let h = NSHostingView(rootView: Probe(model: model, axis: axis, submit: submit))
    let size = CGSize(width: 260, height: 200)
    h.frame = NSRect(origin: .zero, size: size)
    let w = KeyWindow(contentRect: NSRect(origin: CGPoint(x: 100, y: 100), size: size), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    keep.append(w)
    spin(0.4)
    guard let field = findTextViews(h).first else { print(label, "no field"); return }
    w.makeFirstResponder(field)
    spin(0.2)
    func key(_ chars: String, _ ignoring: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ name: String) {
        model.text = "ab"
        spin(0.1)
        // Put the caret between a and b by sending Left once from the end.
        if let editor = w.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: 1, length: 0)) }
        spin(0.05)
        let before = model.submits
        guard let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: code) else { return }
        w.sendEvent(ev)
        if let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: code) { w.sendEvent(up) }
        spin(0.15)
        var caret = "?"
        if let editor = w.firstResponder as? NSTextView { caret = "\(editor.selectedRange().location)+\(editor.selectedRange().length)" }
        print(label, name.padding(toLength: 14, withPad: " ", startingAt: 0), "text=\(model.text.debugDescription) scalars=\(model.text.unicodeScalars.map { String($0.value, radix: 16) }) submits=+\(model.submits - before) caret=\(caret) responder=\(type(of: w.firstResponder!))")
        // Re-focus if the key ended editing.
        w.makeFirstResponder(field)
        spin(0.1)
    }
    key("\r", "\r", 36, [], "Return")
    key("\r", "\r", 36, [.option], "Option-Return")
    key("\r", "\r", 36, [.control], "Ctrl-Return")
    key("\r", "\r", 36, [.shift], "Shift-Return")
    key("\u{3}", "\u{3}", 76, [.numericPad], "Enter(kp)")
    key("\u{f}", "o", 31, [.control], "Ctrl-O")
    key("\n", "j", 38, [.control], "Ctrl-J")
    key("\r", "m", 46, [.control], "Ctrl-M")
    w.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            run(axis: .vertical, submit: true, label: "vertical+onSubmit ")
            run(axis: .vertical, submit: false, label: "vertical, no submit")
            run(axis: .horizontal, submit: true, label: "horizontal+onSubmit")
            run(axis: nil, submit: true, label: "plain+onSubmit     ")
        }
    }
}
