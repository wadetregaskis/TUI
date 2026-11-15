// What becomes of a text editor's undo steps when the editor leaves the window
// while what it edited lives on: a SwiftUI `TextEditor` behind an `if`, and a
// plain `NSTextView` taken out of its window.
//
// SwiftUI: a window (an NSHostingView in an NSWindow, whose undo manager the
// views' `\.undoManager` is) holding `if shown { TextEditor(text: $model.text) }`.
// Text is typed into the editor's NSTextView as the keyboard's insertText does;
// then `shown` goes false, the run loop turns, and the window's undo manager is
// asked whether it can undo, and undoes, with the model's text read after each.
// Then the same with the editor shown again before the undo, and with the app
// replacing the text (`model.text = "xyz"`) in place of hiding the editor, and
// with a `TextField` in the editor's place (typed into through its field
// editor).
//
// AppKit: an NSTextView typed into, removed from its window (kept, then
// released), and the window's undo manager asked the same.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 editorundo.swift -o "$TMPDIR/editorundo"
//   "$TMPDIR/editorundo"
import AppKit
import SwiftUI

@MainActor @Observable final class Model {
    var text = "a"
    var shown = true
}

struct Editor: View {
    @Bindable var model: Model
    var field = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack {
            Text("text: \(model.text)")
            if model.shown {
                if field {
                    TextField("field", text: $model.text).frame(width: 300)
                } else {
                    TextEditor(text: $model.text).frame(width: 300, height: 100)
                }
            }
        }
        .frame(width: 400, height: 200)
        .onAppear { Seen.undoManager = undoManager }
    }
}

@MainActor enum Seen {
    static var undoManager: UndoManager?
}

@MainActor func turn(_ seconds: Double = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@MainActor func textView(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView { return text }
    for sub in view.subviews { if let found = textView(in: sub) { return found } }
    return nil
}

@MainActor func textField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    for sub in view.subviews { if let found = textField(in: sub) { return found } }
    return nil
}

@MainActor func swiftUICase(showAgainBeforeUndo: Bool, replaceInstead: Bool = false, field: Bool = false) {
    let model = Model()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
        defer: false)
    window.contentView = NSHostingView(rootView: Editor(model: model, field: field))
    window.makeKeyAndOrderFront(nil)
    turn(0.3)
    if field, let textField = textField(in: window.contentView!) {
        window.makeFirstResponder(textField)
        turn()
    }
    guard let editor = field ? window.firstResponder as? NSTextView : textView(in: window.contentView!) else {
        print("swiftui: no NSTextView found")
        return
    }
    window.makeFirstResponder(editor)
    turn()
    editor.setSelectedRange(NSRange(location: 1, length: 0))
    for ch in "bc" {
        editor.insertText(String(ch), replacementRange: editor.selectedRange())
        turn()
    }
    let manager = window.undoManager
    print(
        "swiftui\(field ? " TextField" : "")\(showAgainBeforeUndo ? " (shown again)" : ""): typed bc -> text \(model.text.debugDescription); "
            + "window manager is \\.undoManager: \(manager === Seen.undoManager); canUndo \(manager?.canUndo ?? false)")
    if replaceInstead {
        model.text = "xyz"
        turn(0.3)
        print("  app replaced the text -> editor shows \(editor.string.debugDescription); canUndo \(manager?.canUndo ?? false)")
    } else {
        model.shown = false
        turn(0.3)
        print("  hidden -> editor in window: \(textView(in: window.contentView!) != nil); canUndo \(manager?.canUndo ?? false)")
    }
    if showAgainBeforeUndo {
        model.shown = true
        turn(0.3)
        print("  shown again -> canUndo \(manager?.canUndo ?? false)")
    }
    if manager?.canUndo == true {
        manager?.undo()
        turn(0.3)
        print("  undo -> text \(model.text.debugDescription); canUndo \(manager?.canUndo ?? false); canRedo \(manager?.canRedo ?? false)")
        if manager?.canRedo == true {
            manager?.redo()
            turn(0.3)
            print("  redo -> text \(model.text.debugDescription)")
        }
    }
    window.orderOut(nil)
}

@MainActor func appKitCase(release: Bool) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
        defer: false)
    var view: NSTextView? = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view!.allowsUndo = true
    view!.string = "a"
    window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
    window.contentView!.addSubview(view!)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    view!.setSelectedRange(NSRange(location: 1, length: 0))
    for ch in "bc" {
        view!.insertText(String(ch), replacementRange: view!.selectedRange())
        turn()
    }
    let manager = window.undoManager
    print("appkit\(release ? " (released)" : ""): typed bc -> \(view!.string.debugDescription); canUndo \(manager?.canUndo ?? false)")
    view!.removeFromSuperview()
    let weakView = WeakBox(view)
    if release { view = nil }
    turn(0.3)
    print("  removed -> view alive \(weakView.value != nil); canUndo \(manager?.canUndo ?? false)")
    if manager?.canUndo == true {
        manager?.undo()
        turn()
        print("  undo -> view text \((weakView.value?.string ?? "<gone>").debugDescription); canRedo \(manager?.canRedo ?? false)")
    }
    window.orderOut(nil)
}

final class WeakBox {
    weak var value: NSTextView?
    init(_ value: NSTextView?) { self.value = value }
}

@main
struct Probe {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            swiftUICase(showAgainBeforeUndo: false)
            swiftUICase(showAgainBeforeUndo: true)
            print("swiftui, the app replacing the text instead of hiding the editor:")
            swiftUICase(showAgainBeforeUndo: false, replaceInstead: true)
            swiftUICase(showAgainBeforeUndo: false, field: true)
            appKitCase(release: false)
            appKitCase(release: true)
        }
    }
}
