import AppKit
import SwiftUI

// FOCUS-5 (hunt 2026-11-20, H-70, owner ruling O-13): does
// `.defaultFocus(_:_:priority: .userInitiated)` keep re-applying its default
// on every pass, or once? Does Tab, a click or a `@FocusState` write win
// afterwards, and when is the default applied again?
//
// Each case hosts text fields, named by their text, in a 300 × 260 point key
// window and prints the field holding the focus (the window's first
// responder) and the `@FocusState` value the view last saw, after each step:
//
// - start: after the window has appeared and settled;
// - tab, shift-tab: the key sent through the window (`NSWindow.sendEvent`,
//   as the keyboard would);
// - click X: a mouse down and up on field X's centre, through the window;
// - write X: the app sets its `@FocusState` to X (from `onChange` of a model
//   value, as an app's own code would), X `nil` included;
// - render: the body re-evaluated (a counter it draws is bumped) with no
//   focus change asked for — where a default that re-applies every pass
//   would take the focus back.
//
// Text fields, because Tab and a click reach them without Full Keyboard
// Access. Cases, each with no default (the control), `.automatic` and
// `.userInitiated`:
//
// - page: three fields a, b, c, `.defaultFocus($f, .b)` on their VStack;
// - region: a field "out" above a VStack of r1, r2, r3 carrying
//   `.defaultFocus($f, .r2)`; "out" is focused first (a click), then Tab
//   enters the region, Shift-Tab leaves it and Tab enters it again — where a
//   default that applies to navigation INTO its region would send the focus
//   to r2 rather than r1.
//
//   swiftc -parse-as-library defaultfocus.swift -o /tmp/df && /tmp/df

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func fields(_ v: NSView) -> [NSTextField] {
    var out: [NSTextField] = []
    if let f = v as? NSTextField, f.isEditable { out.append(f) }
    for c in v.subviews { out += fields(c) }
    return out
}

@MainActor func focused(_ window: NSWindow) -> String {
    guard let responder = window.firstResponder else { return "nothing" }
    if let editor = responder as? NSTextView, editor.isFieldEditor,
       let field = editor.delegate as? NSTextField {
        return field.stringValue
    }
    if let field = responder as? NSTextField { return field.stringValue }
    return "nothing (\(type(of: responder)))"
}

@MainActor func key(_ window: NSWindow, shift: Bool = false) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: shift ? "\u{19}" : "\t",
            charactersIgnoringModifiers: shift ? "\u{19}" : "\t", isARepeat: false, keyCode: 48)!
        window.sendEvent(event)
    }
}

@MainActor func click(_ window: NSWindow, _ hosting: NSView, _ name: String) {
    guard let field = fields(hosting).first(where: { $0.stringValue == name }) else {
        print("    (no field \(name))")
        return
    }
    let rect = field.convert(field.bounds, to: nil)
    let point = NSPoint(x: rect.midX, y: rect.midY)
    func event(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    // The up is queued before the down is sent: a text field's mouse down
    // tracks the mouse until an up arrives, and would otherwise wait for ever.
    NSApp.postEvent(event(.leftMouseUp), atStart: false)
    window.sendEvent(event(.leftMouseDown))
}

/// What the probe asks of the hosted view: a body re-evaluation, a
/// `@FocusState` write.
final class Model: ObservableObject {
    @Published var tick = 0
    @Published var write: Request?
    /// The `@FocusState` value as the view last saw it change.
    var seen: String?
}

struct Request: Equatable {
    let serial: Int
    let value: String?
}

struct Field: View {
    let name: String
    @State var text: String
    init(_ name: String) { self.name = name; _text = State(initialValue: name) }
    var body: some View { TextField("", text: $text) }
}

extension View {
    /// `.defaultFocus` at `priority`, or none at all for the control case.
    @ViewBuilder func defaultFocus(
        _ binding: FocusState<String?>.Binding, _ value: String, ifAny priority: DefaultFocusEvaluationPriority?
    ) -> some View {
        if let priority { defaultFocus(binding, value, priority: priority) } else { self }
    }
}

struct Page: View {
    @ObservedObject var model: Model
    let priority: DefaultFocusEvaluationPriority?
    @FocusState var f: String?
    var body: some View {
        VStack {
            Text("tick \(model.tick)")
            Field("a").focused($f, equals: "a")
            Field("b").focused($f, equals: "b")
            Field("c").focused($f, equals: "c")
        }
        .defaultFocus($f, "b", ifAny: priority)
        .onChange(of: model.write) { _, request in f = request?.value }
        .onChange(of: f, initial: true) { _, value in model.seen = value }
    }
}

struct Region: View {
    @ObservedObject var model: Model
    let priority: DefaultFocusEvaluationPriority?
    @FocusState var f: String?
    var body: some View {
        VStack {
            Text("tick \(model.tick)")
            Field("out").focused($f, equals: "out")
            VStack {
                Field("r1").focused($f, equals: "r1")
                Field("r2").focused($f, equals: "r2")
                Field("r3").focused($f, equals: "r3")
            }
            .defaultFocus($f, "r2", ifAny: priority)
        }
        .onChange(of: model.write) { _, request in f = request?.value }
        .onChange(of: f, initial: true) { _, value in model.seen = value }
    }
}

enum Step {
    case tab, backtab, click(String), write(String?), render
}

@MainActor func state(_ window: NSWindow, _ model: Model) -> String {
    "\(focused(window)), f = \(model.seen ?? "nil")"
}

@MainActor func run<V: View>(_ name: String, model: Model, _ view: V, _ steps: [Step]) {
    let size = NSSize(width: 300, height: 260)
    let window = KeyWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 300), size: size),
                           styleMask: [.titled], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    spin(0.5)
    var log = ["start: \(state(window, model))"]
    var serial = 0
    for step in steps {
        let label: String
        switch step {
        case .tab: key(window); label = "tab"
        case .backtab: key(window, shift: true); label = "shift-tab"
        case .click(let target): click(window, hosting, target); label = "click \(target)"
        case .write(let value):
            serial += 1
            model.write = Request(serial: serial, value: value)
            label = "write \(value ?? "nil")"
        case .render: model.tick += 1; label = "render"
        }
        spin()
        log.append("\(label): \(state(window, model))")
    }
    print(name)
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
            let pageSteps: [Step] = [
                .render, .tab, .render, .tab, .render, .click("a"), .render, .click("c"), .render,
                .write("a"), .render, .write("c"), .render, .write(nil), .render, .tab, .render,
            ]
            let regionSteps: [Step] = [
                .click("out"), .render, .tab, .render, .tab, .render, .backtab, .backtab, .render,
                .tab, .render, .click("r3"), .render, .write("out"), .render, .tab, .render,
            ]
            for (label, priority) in [("no default", nil), ("automatic", DefaultFocusEvaluationPriority.automatic),
                                      ("userInitiated", .userInitiated)] {
                let page = Model()
                run("page, \(label)", model: page, Page(model: page, priority: priority), pageSteps)
                let region = Model()
                run("region, \(label)", model: region, Region(model: region, priority: priority), regionSteps)
            }
            exit(0)
        }
    }
}
