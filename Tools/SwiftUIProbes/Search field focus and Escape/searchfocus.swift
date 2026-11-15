// Where the focus starts in a window whose content is `.searchable`, and what
// Escape does in the search field, with text and then empty: the query, the
// `isSearching` the content reads, and which view is the first responder.
//
// A SwiftUI app with one WindowGroup, as an app's window is, its search field
// in the toolbar (`com.apple.SwiftUI.search`); `CONTENT` picks the content:
// `list` (a List with a selection), `table` (a Table), or `text` (a Text,
// nothing focusable). It reports and quits by itself. The app activates itself
// once its window appears, as one opened from the Dock is active; a bare
// executable is not otherwise.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 searchfocus.swift -o "$TMPDIR/searchfocus"
//   for c in list table text; do CONTENT=$c "$TMPDIR/searchfocus"; done
//
// Not an argument: AppKit reads one as a document to open, and a WindowGroup
// then opens no window.
import AppKit
import SwiftUI

/// What the content saw last, and the query, readable from outside the views.
@MainActor enum Seen {
    static var isSearching = false
    static var query = ""
}

struct Row: Identifiable {
    let id: Int
    var name: String { "Row \(id)" }
}

struct Content: View {
    let kind: String
    @State private var selection: Int?
    @Environment(\.isSearching) private var isSearching
    private let rows = (0..<5).map(Row.init)

    var body: some View {
        Group {
            switch kind {
            case "table":
                Table(rows, selection: $selection) { TableColumn("Name", value: \.name) }
            case "text":
                Text("Nothing focusable")
            default:
                List(rows, selection: $selection) { Text($0.name) }
            }
        }
        .onChange(of: isSearching, initial: true) { _, now in Seen.isSearching = now }
    }
}

struct Window: View {
    let kind: String
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Content(kind: kind)
                .searchable(text: $query)
        }
        // Wide enough that the toolbar has room for the field.
        .frame(minWidth: 900, minHeight: 400)
        .onChange(of: query, initial: true) { _, now in Seen.query = now }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct SearchFocusProbe: App {
    private let kind = ProcessInfo.processInfo.environment["CONTENT"] ?? "list"

    init() {
        Steps.after(3) { Steps.run() }
    }

    var body: some Scene {
        WindowGroup { Window(kind: kind) }
    }
}

@MainActor enum Steps {
    static var window: NSWindow? { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } }

    /// The first responder, named: the search field when it is the field
    /// editor of an NSSearchField.
    static func responder() -> String {
        guard let window else { return "no window" }
        guard let responder = window.firstResponder else { return "nil" }
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            let owner = editor.delegate.map { String(describing: type(of: $0)) } ?? "?"
            return "field editor of \(owner)"
        }
        return String(describing: type(of: responder))
    }

    static func report(_ moment: String) {
        print(
            "\(moment): first responder = \(responder()); query = \"\(Seen.query)\"; "
                + "isSearching = \(Seen.isSearching)")
    }

    /// Escape, as the keyboard delivers it to the key window.
    static func pressEscape() {
        guard let window,
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)
        else { return }
        window.sendEvent(event)
    }

    /// The search field, wherever in the window's frame view (which holds the
    /// titlebar and its toolbar) it is.
    static func searchField() -> NSSearchField? {
        func find(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            for subview in view.subviews {
                if let field = find(in: subview) { return field }
            }
            return nil
        }
        return window?.contentView?.superview.flatMap(find(in:))
    }

    static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
    }

    static func run() {
        print("content: \(ProcessInfo.processInfo.environment["CONTENT"] ?? "list"); app active: \(NSApp.isActive)")
        print("toolbar items: \(window?.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])")
        report("at launch")
        guard let field = searchField() else {
            print("no search field")
            NSApp.terminate(nil)
            return
        }
        window?.makeFirstResponder(field)
        after(0.5) {
            report("search field clicked")
            field.currentEditor()?.insertText("abc")
            after(0.5) {
                report("typed abc")
                pressEscape()
                after(0.5) {
                    report("Escape with text")
                    pressEscape()
                    after(0.5) {
                        report("Escape again")
                        window?.makeFirstResponder(field)
                        after(0.5) {
                            report("search field clicked, empty")
                            pressEscape()
                            after(0.5) {
                                report("Escape in the empty field")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }
}
