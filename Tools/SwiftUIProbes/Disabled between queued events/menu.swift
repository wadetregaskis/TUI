import AppKit
import SwiftUI

// A CommandMenu item's `.disabled`, written by its own action, with a second
// key equivalent queued right behind the first. A real `App`, because a
// `.commands` scene needs one. PROBE_CONTROL=1 leaves the `.disabled` off, so
// that one action cannot be a dropped event.

@MainActor final class Model: ObservableObject {
    @Published var isSaving = false
    var actions = 0
}

@MainActor let model = Model()
let gated = ProcessInfo.processInfo.environment["PROBE_CONTROL"] == nil

@main struct MenuProbe: App {
    @StateObject var state = model
    var body: some Scene {
        WindowGroup {
            Color.gray.frame(width: 200, height: 200).task { await script() }
        }
        .commands { ProbeCommands(state: state) }
    }
}

// A `Commands` of its own observing the model, the form Apple's documentation
// shows; the same menu written inline in the scene gave the same result.
struct ProbeCommands: Commands {
    @ObservedObject var state: Model
    var body: some Commands {
        CommandMenu("Probe") {
            Button("Save") {
                state.actions += 1
                state.isSaving = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(gated && state.isSaving)
        }
    }
}

@MainActor func script() async {
    setvbuf(stdout, nil, _IOLBF, 0)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    try? await Task.sleep(for: .milliseconds(500))
    guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else {
        print("no window"); exit(1)
    }
    window.makeKeyAndOrderFront(nil)
    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    try? await Task.sleep(for: .milliseconds(300))
    let items = NSApp.mainMenu?.items.first { $0.title == "Probe" }?.submenu?.items ?? []
    print("gated=\(gated) item=\(items.map(\.title)) key=\(window.isKeyWindow) active=\(NSApp.isActive)")
    func key(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
    }
    func item() -> Bool? {
        NSApp.mainMenu?.items.first { $0.title == "Probe" }?.submenu?.items.first?.isEnabled
    }
    let paused = ProcessInfo.processInfo.environment["PROBE_PAUSED"] != nil
    for (index, event) in [key(.keyDown), key(.keyUp), key(.keyDown), key(.keyUp)].enumerated() {
        NSApp.postEvent(event, atStart: false)
        if paused, index == 1 {
            try? await Task.sleep(for: .milliseconds(500))
            print("after first: actions=\(model.actions) itemEnabled=\(item().map(String.init(describing:)) ?? "none")")
        }
    }
    try? await Task.sleep(for: .milliseconds(800))
    print((paused ? "paused" : "batched") + ": actions=\(model.actions) itemEnabled=\(item().map(String.init(describing:)) ?? "none")")
    exit(0)
}
