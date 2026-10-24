import AppKit

// Review follow-up (lane INPUT, 2026-10-18): what ends NSTextView's typing
// coalescing beyond the cases of ../undo: the first responder moving to
// another text view sharing the window's undo manager and back; an unrelated
// undo registered on that manager mid-run; Option-Return and Ctrl-O through
// the key bindings.
@MainActor
func run() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let a = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    let b = NSTextView(frame: NSRect(x: 0, y: 100, width: 400, height: 100))
    for view in [a, b] { view.allowsUndo = true; view.isRichText = false; content.addSubview(view) }
    window.contentView = content
    window.makeFirstResponder(a)
    let undo = window.undoManager!

    func turn(_ seconds: Double = 0.01) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    func type(_ s: String, into view: NSTextView) {
        for ch in s {
            view.insertText(String(ch), replacementRange: view.selectedRange())
            turn()
        }
    }
    func state() -> String { "A=\(a.string.debugDescription) B=\(b.string.debugDescription)" }
    func undoOnce() -> String {
        undo.undo(); turn(); return state()
    }
    func reset() {
        a.string = ""; b.string = ""
        undo.removeAllActions()
        a.breakUndoCoalescing(); b.breakUndoCoalescing()
        window.makeFirstResponder(a)
        turn()
    }
    func key(_ chars: String, ignoring: String, flags: NSEvent.ModifierFlags, code: UInt16, into view: NSTextView) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: chars, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: code)!
        view.interpretKeyEvents([event])
        turn()
    }

    // 1. Focus to another text view and back, the caret unchanged.
    reset(); type("ab", into: a)
    window.makeFirstResponder(b); turn(); type("x", into: b)
    window.makeFirstResponder(a); turn()
    print("1 sel after return", a.selectedRange())
    type("c", into: a)
    print("1 A ab, B x, A c; undo ->", undoOnce(), "| again ->", undoOnce(), "| again ->", undoOnce())
    // 2. Focus away and back with nothing typed elsewhere.
    reset(); type("ab", into: a)
    window.makeFirstResponder(b); turn(); window.makeFirstResponder(a); turn(); type("c", into: a)
    print("2 A ab, focus B, back, c; undo ->", undoOnce(), "| again ->", undoOnce())
    // 3. An unrelated undo registered mid-run.
    reset(); type("ab", into: a)
    final class Target: NSObject { @objc func noop(_: Any?) {} }
    let target = Target()
    undo.registerUndo(withTarget: target, selector: #selector(Target.noop(_:)), object: nil)
    undo.setActionName("other")
    turn()
    type("c", into: a)
    print("3 A ab, other action, c; undo ->", undoOnce(), "| again ->", undoOnce(), "| again ->", undoOnce())
    // 4. Option-Return in a run.
    reset(); type("ab", into: a)
    key("\r", ignoring: "\r", flags: .option, code: 36, into: a)
    print("4 sel after opt-return", a.selectedRange())
    type("cd", into: a)
    print("4 ab, opt-return, cd; undo ->", undoOnce(), "| again ->", undoOnce())
    // 5. Ctrl-O in a run.
    reset(); type("ab", into: a)
    key("\u{0f}", ignoring: "o", flags: .control, code: 31, into: a)
    print("5 text after ctrl-o", a.string.debugDescription, "sel", a.selectedRange())
    print("5 ab, ctrl-o; undo ->", undoOnce(), "| again ->", undoOnce())
    // 6. Ctrl-O then typing at the caret it leaves.
    reset(); type("ab", into: a)
    key("\u{0f}", ignoring: "o", flags: .control, code: 31, into: a)
    type("cd", into: a)
    print("6 ab, ctrl-o, cd; text", a.string.debugDescription, "undo ->", undoOnce(), "| again ->", undoOnce(), "| again ->", undoOnce())
    // 7. Plain Return through the key bindings, for comparison.
    reset(); type("ab", into: a)
    key("\r", ignoring: "\r", flags: [], code: 36, into: a)
    type("cd", into: a)
    print("7 ab, return, cd; undo ->", undoOnce(), "| again ->", undoOnce())
    // 8. Option-Tab (insertTabIgnoringFieldEditor:) in a run.
    reset(); type("ab", into: a)
    key("\t", ignoring: "\t", flags: .option, code: 48, into: a)
    type("cd", into: a)
    print("8 ab, opt-tab, cd; text", a.string.debugDescription, "undo ->", undoOnce(), "| again ->", undoOnce())
}

MainActor.assumeIsolated { run() }
