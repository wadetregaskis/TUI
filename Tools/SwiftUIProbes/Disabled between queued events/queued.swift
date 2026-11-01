import AppKit
import SwiftUI

// Does a `.disabled` written by one activation apply before a second activation
// that is already queued right behind it?
//
// Every case posts ALL its events in one go, from inside one main-queue job, so
// they are sitting in the queue together before AppKit dequeues the first; the
// real `NSApp.run()` then delivers them. Each runs three ways: `control` applies
// no `.disabled`, so that "one action" cannot be a dropped event; `gated` applies
// it; `paused` applies it with 0.3 s between the presses, the check that the
// gated case's answer is the batch's and not the view's. `body` runs are counted,
// and each action records how many had happened by then: a second action with a
// higher count means the view updated between the two events even if the action
// ran anyway.

@MainActor var actions: [Int] = []
@MainActor var bodyRuns = 0
@MainActor func act() { actions.append(bodyRuns) }

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct Plain: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") { act(); isSaving = true }.buttonStyle(.plain).disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Bordered: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") { act(); isSaving = true }.disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
// The issue's exact shape: the write, then a Task that clears it much later.
struct IssueForm: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") {
            act()
            isSaving = true
            Task { try? await Task.sleep(for: .seconds(30)); isSaving = false }
        }
        .disabled(gated && isSaving)
        .frame(width: 200, height: 200)
    }
}
// The other common shape: the write is the first thing a Task does, so nothing
// has changed when the action returns.
struct TaskWrite: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") {
            act()
            Task { isSaving = true; try? await Task.sleep(for: .seconds(30)); isSaving = false }
        }
        .disabled(gated && isSaving)
        .frame(width: 200, height: 200)
    }
}
struct TaskWriteKey: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") {
            act()
            Task { isSaving = true; try? await Task.sleep(for: .seconds(30)); isSaving = false }
        }
        .keyboardShortcut("k", modifiers: .command)
        .disabled(gated && isSaving)
        .frame(width: 200, height: 200)
    }
}
struct Tap: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Color.gray.onTapGesture { act(); isSaving = true }.disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Check: View {
    let gated: Bool
    @State var isSaving = false
    @State var isOn = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Toggle("Save", isOn: Binding(get: { isOn }, set: { isOn = $0; act(); isSaving = true }))
            .toggleStyle(.checkbox).disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Hyper: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Link("Save", destination: URL(string: "https://example.com")!)
            .environment(\.openURL, OpenURLAction { _ in act(); isSaving = true; return .handled })
            .disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Return: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") { act(); isSaving = true }.keyboardShortcut(.defaultAction).disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Shortcut: View {
    let gated: Bool
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        Button("Save") { act(); isSaving = true }.keyboardShortcut("k", modifiers: .command).disabled(gated && isSaving)
            .frame(width: 200, height: 200)
    }
}
struct Submit: View {
    let gated: Bool
    @State var text = ""
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        TextField("Name", text: $text).onSubmit { act(); isSaving = true }.disabled(gated && isSaving)
            .frame(width: 180, height: 30).frame(width: 200, height: 200)
    }
}
struct Editing: View {
    let gated: Bool
    @State var text = ""
    @State var isSaving = false
    var body: some View {
        let _ = (bodyRuns += 1)
        // Typing, not an activation: a character disables the field. Only a real
        // change counts, as the field also calls the setter as it gains focus.
        TextField("Name", text: Binding(get: { text }, set: { if $0 != text { text = $0; act(); isSaving = true } }))
            .disabled(gated && isSaving)
            .frame(width: 180, height: 30).frame(width: 200, height: 200)
    }
}

@MainActor func find(_ view: NSView, _ want: (NSView) -> Bool) -> NSView? {
    if want(view) { return view }
    for sub in view.subviews { if let hit = find(sub, want) { return hit } }
    return nil
}

@MainActor func mouse(_ window: NSWindow, _ type: NSEvent.EventType, clickCount: Int) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)!
}

@MainActor func key(
    _ window: NSWindow, _ type: NSEvent.EventType, _ chars: String, code: UInt16,
    mods: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
        isARepeat: false, keyCode: code)!
}

@MainActor func twoClicks(_ w: NSWindow) -> [NSEvent] {
    [mouse(w, .leftMouseDown, clickCount: 1), mouse(w, .leftMouseUp, clickCount: 1),
     mouse(w, .leftMouseDown, clickCount: 2), mouse(w, .leftMouseUp, clickCount: 2)]
}
@MainActor func twoKeys(_ w: NSWindow, _ c: String, code: UInt16, mods: NSEvent.ModifierFlags = []) -> [NSEvent] {
    [key(w, .keyDown, c, code: code, mods: mods), key(w, .keyUp, c, code: code, mods: mods),
     key(w, .keyDown, c, code: code, mods: mods), key(w, .keyUp, c, code: code, mods: mods)]
}

let onScreen = ProcessInfo.processInfo.environment["PROBE_ONSCREEN"] != nil
@MainActor var keep: [NSWindow] = []

/// Hosts `view`, settles, posts `events` all at once, lets the run loop deliver
/// them, and prints what happened.
@MainActor func run<V: View>(
    _ label: String, _ view: V, gap: Double = 0, focus: ((NSWindow) -> Void)? = nil,
    events: (NSWindow) -> [NSEvent]
) async {
    actions = []
    bodyRuns = 0
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
    let origin = onScreen ? CGPoint(x: 80, y: 80) : CGPoint(x: -5000, y: -5000)
    let window = KeyableWindow(
        contentRect: NSRect(origin: origin, size: host.frame.size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    keep.append(window)
    try? await Task.sleep(for: .milliseconds(350))
    focus?(window)
    try? await Task.sleep(for: .milliseconds(100))
    let before = bodyRuns
    let list = events(window)
    if gap == 0 {
        for event in list { NSApp.postEvent(event, atStart: false) }
    } else {
        for (index, event) in list.enumerated() {
            NSApp.postEvent(event, atStart: false)
            if index == 1 { try? await Task.sleep(for: .seconds(gap)) }
        }
    }
    try? await Task.sleep(for: .milliseconds(800))
    let at = actions.map { "\($0 - before)" }.joined(separator: ",")
    print("\(label): actions=\(actions.count) body-runs-before-each=[\(at)] body-runs-total=\(bodyRuns - before)")
    window.orderOut(nil)
}

@MainActor func trio<V: View>(
    _ label: String, _ make: (Bool) -> V, focus: ((NSWindow) -> Void)? = nil, events: (NSWindow) -> [NSEvent]
) async {
    await run("\(label) control", make(false), focus: focus, events: events)
    await run("\(label) gated  ", make(true), focus: focus, events: events)
    await run("\(label) paused ", make(true), gap: 0.3, focus: focus, events: events)
}

@MainActor func focusButton(_ w: NSWindow) {
    if let b = find(w.contentView!, { $0 is NSButton }) { w.makeFirstResponder(b) }
}
@MainActor func focusField(_ w: NSWindow) {
    if let f = find(w.contentView!, { $0 is NSTextField }) { w.makeFirstResponder(f) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.finishLaunching()
            print("onScreen=\(onScreen) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            Task { @MainActor in
                await trio("button plain     click ", { Plain(gated: $0) }, events: twoClicks)
                await trio("button bordered  click ", { Bordered(gated: $0) }, events: twoClicks)
                await trio("issue's form     click ", { IssueForm(gated: $0) }, events: twoClicks)
                await trio("write in a Task  click ", { TaskWrite(gated: $0) }, events: twoClicks)
                await trio("write in a Task  cmd-k ", { TaskWriteKey(gated: $0) }) {
                    twoKeys($0, "k", code: 40, mods: .command)
                }
                await trio("onTapGesture     click ", { Tap(gated: $0) }, events: twoClicks)
                await trio("toggle checkbox  click ", { Check(gated: $0) }, events: twoClicks)
                await trio("link             click ", { Hyper(gated: $0) }, events: twoClicks)
                await trio("focused button   space ", { Bordered(gated: $0) }, focus: focusButton) {
                    twoKeys($0, " ", code: 49)
                }
                await trio("defaultAction    return", { Return(gated: $0) }) { twoKeys($0, "\r", code: 36) }
                await trio("keyboardShortcut cmd-k ", { Shortcut(gated: $0) }) {
                    twoKeys($0, "k", code: 40, mods: .command)
                }
                await trio("onSubmit         return", { Submit(gated: $0) }, focus: focusField) {
                    twoKeys($0, "\r", code: 36)
                }
                await trio("textfield typing a a   ", { Editing(gated: $0) }, focus: focusField) {
                    twoKeys($0, "a", code: 0)
                }
                exit(0)
            }
            NSApp.run()
        }
    }
}
