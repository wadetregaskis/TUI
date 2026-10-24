import AppKit

// Does NSTextView coalesce a run of typing into one undo step, and what ends
// the run: a pause, a caret move, a deletion?
@MainActor
func run() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.allowsUndo = true
    window.contentView = view
    window.makeFirstResponder(view)
    let undo = window.undoManager!

    func turn(_ seconds: Double = 0.01) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    func type(_ s: String) {
        for ch in s {
            view.insertText(String(ch), replacementRange: view.selectedRange())
            turn()
        }
    }
    func undoOnce() -> String {
        undo.undo(); turn(); return view.string
    }
    func reset() {
        view.string = ""
        undo.removeAllActions()
        view.breakUndoCoalescing()
        turn()
    }

    // 1. A run of typing.
    reset(); type("abc"); print("1 typed abc; undo once ->", undoOnce().debugDescription)
    // 2. A pause of 2 s in the middle.
    reset(); type("ab"); turn(2.0); type("cd"); print("2 ab, pause 2s, cd; undo once ->", undoOnce().debugDescription)
    // 3. A caret move in the middle (away and back).
    reset(); type("ab"); view.setSelectedRange(NSRange(location: 0, length: 0)); turn()
    view.setSelectedRange(NSRange(location: 2, length: 0)); turn(); type("cd")
    print("3 ab, caret away and back, cd; undo once ->", undoOnce().debugDescription)
    // 4. A caret move elsewhere.
    reset(); type("ab"); view.setSelectedRange(NSRange(location: 0, length: 0)); turn(); type("cd")
    print("4 ab, caret to start, cd; undo once ->", undoOnce().debugDescription)
    // 5. A deletion in the middle.
    reset(); type("abc"); view.deleteBackward(nil); turn(); type("de")
    print("5 abc, backspace, de; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription,
          "again ->", undoOnce().debugDescription)
    // 6. Two deletions.
    reset(); type("abcd"); view.breakUndoCoalescing(); view.deleteBackward(nil); turn(); view.deleteBackward(nil); turn()
    print("6 abcd, (break), backspace twice; undo once ->", undoOnce().debugDescription)
    // 7. A newline in the middle.
    reset(); type("ab"); view.insertNewline(nil); turn(); type("cd")
    print("7 ab, newline, cd; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 8. A space between words.
    reset(); type("ab cd"); print("8 'ab cd'; undo once ->", undoOnce().debugDescription)
    // 9. Typing over a selection.
    reset(); type("abcd"); view.breakUndoCoalescing(); view.setSelectedRange(NSRange(location: 1, length: 2)); turn(); type("XY")
    print("9 abcd, select bc, type XY; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 10. Forward delete in the middle of a run.
    reset(); type("abc"); view.setSelectedRange(NSRange(location: 1, length: 0)); turn()
    view.setSelectedRange(NSRange(location: 3, length: 0)); turn()
    view.moveLeft(nil); turn(); view.deleteForward(nil); turn(); type("Z")
    print("10 abc, left, forward-delete, Z; text", view.string.debugDescription, "undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 11. Paste in the middle of a run.
    reset(); type("ab")
    let pb = NSPasteboard.general; pb.clearContents(); pb.setString("PP", forType: .string)
    view.paste(nil); turn(); type("cd")
    print("11 ab, paste PP, cd; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 12. Word delete in a run.
    reset(); type("ab cd"); view.deleteWordBackward(nil); turn(); type("ef")
    print("12 'ab cd', word-delete, ef; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 13. Backspace first, then typing (after a break).
    reset(); type("abc"); view.breakUndoCoalescing(); view.deleteBackward(nil); turn(); type("de")
    print("13 abc, (break), backspace, de; undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 14. Undo then type: redo gone, new run.
    reset(); type("ab"); _ = undoOnce(); type("cd"); print("14 ab, undo, cd; undo once ->", undoOnce().debugDescription)
    // 15. Backspace over a selection, then typing.
    reset(); type("abcd"); view.breakUndoCoalescing(); view.setSelectedRange(NSRange(location: 1, length: 2)); turn()
    view.deleteBackward(nil); turn(); type("XY")
    print("15 abcd, select bc, backspace, XY; text", view.string.debugDescription, "undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
    // 16. Tab in a run.
    reset(); type("ab"); view.insertTab(nil); turn(); type("cd")
    print("16 ab, tab, cd; undo once ->", undoOnce().debugDescription)
    // 17. Typing over a selection that ends where the run ended.
    reset(); type("abcd"); view.setSelectedRange(NSRange(location: 2, length: 2)); turn(); type("X")
    print("17 abcd, select cd (run end), X; text", view.string.debugDescription, "undo once ->", undoOnce().debugDescription, "again ->", undoOnce().debugDescription)
}

MainActor.assumeIsolated { run() }
