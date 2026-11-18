import SwiftUI
import AppKit

// In a Form, what becomes of a TextField's title, and of its prompt? Each case
// hosts `Form { A; B }`, A a LabeledContent with a short label, B the field,
// and prints where the AppKit text field SwiftUI made starts and what it
// shows: its placeholder and its value. Also the same fields outside a form,
// for comparison. A title the form draws as the row's label pushes the field
// right of the label column ("empty title + prompt" and "labelsHidden" are the
// rows with no label: the field starts where A's value does); a prompt is the
// field's placeholder. (`rows.out` has the label's own frame, for a label
// view.)
nonisolated(unsafe) var canvas = CGSize(width: 560, height: 160)
@MainActor var keep: [NSWindow] = []

@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: canvas)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: canvas), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func fields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []
    for sub in view.subviews {
        if let f = sub as? NSTextField, f.isEditable { found.append(f) }
        found += fields(in: sub)
    }
    return found
}


@MainActor func aRow() -> some View {
    LabeledContent { Text("v") } label: { Text("A") }
}

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("title, empty", AnyView(TextField("Name", text: .constant("")))),
        ("title, typed", AnyView(TextField("Name", text: .constant("typed")))),
        ("title + prompt, empty", AnyView(TextField("Name", text: .constant(""), prompt: Text("Required")))),
        ("empty title + prompt", AnyView(TextField("", text: .constant(""), prompt: Text("Required")))),
        ("label view, empty", AnyView(TextField(text: .constant("")) { Text("Name") })),
        ("vertical, title, empty", AnyView(TextField("Name", text: .constant(""), axis: .vertical))),
        ("SecureField title, empty", AnyView(SecureField("Name", text: .constant("")))),
        ("title, labelsHidden", AnyView(TextField("Name", text: .constant("")).labelsHidden())),
    ]
    for style in ["none", "columns", "grouped"] {
        print("== \(style)")
        for (name, b) in cases {
            let root: AnyView
            switch style {
            case "none": root = AnyView(VStack { b })
            case "columns": root = AnyView(Form { aRow(); b }.formStyle(.columns))
            default: root = AnyView(Form { aRow(); b }.formStyle(.grouped))
            }
            let h = host(root.frame(width: canvas.width, height: canvas.height, alignment: .topLeading))
            spin()
            h.layoutSubtreeIfNeeded()
            spin(0.1)
            let shown = fields(in: h).map {
                "placeholder=\($0.placeholderString.map { "\"\($0)\"" } ?? "nil") value=\"\($0.stringValue)\""
            }
            let at = fields(in: h).first.map { $0.convert($0.bounds, to: h).minX } ?? -1
            print(
                name.padding(toLength: 26, withPad: " ", startingAt: 0)
                    + String(format: "field from x %5.1f: ", at) + shown.joined(separator: "; "))
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
