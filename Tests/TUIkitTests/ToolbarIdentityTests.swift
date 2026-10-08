//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarIdentityTests.swift
//
//  Where a toolbar item lives: at its place in the declaration that holds it,
//  as a view in a `ViewBuilder` does — not at its index in a flattened list —
//  and apart from the items of every other `.toolbar` on the same view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

/// Whether the conditional item is declared: reachable from an `App`.
private final class ItemSwitch: @unchecked Sendable {
    static let shared = ItemSwitch()
    var on = false
}

/// A toolbar item whose own `@State` counts its presses.
private struct TallyItem: View {
    @State private var count = 0

    var body: some View {
        Button("TALLY \(count)") { count += 1 }
            .keyboardShortcut("c", modifiers: [])
    }
}

/// An item inside an `if`, before an item with state.
private struct ConditionalItemApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    if ItemSwitch.shared.on {
                        ToolbarItem(placement: .primaryAction) { Text("EXTRA") }
                    }
                    ToolbarItem(placement: .primaryAction) { TallyItem() }
                }
        }
    }
}

/// Two `.toolbar`s on one view, with something between them or not.
private struct TwoToolbarsApp: App {
    var padded = false

    init() {}

    init(padded: Bool) { self.padded = padded }

    var body: some Scene {
        WindowGroup {
            if padded {
                Text("PAGE")
                    .toolbar { ToolbarItem { Text("ALPHA") } }
                    .padding()
                    .toolbar { ToolbarItem(placement: .bottomBar) { Text("BETA") } }
            } else {
                Text("PAGE")
                    .toolbar { ToolbarItem { Text("ALPHA") } }
                    .toolbar { ToolbarItem(placement: .bottomBar) { Text("BETA") } }
            }
        }
    }
}

@MainActor
@Suite("A toolbar item's identity", .serialized)
struct ToolbarIdentityTests {

    private func rows(_ app: HeadlessApp<some App>) -> [String] {
        app.screen.map(\.stripped)
    }

    @Test("Two .toolbar modifiers on one view both put their items in the bars", arguments: [false, true])
    func twoToolbarsOnOneView(padded: Bool) {
        let app = HeadlessApp(TwoToolbarsApp(padded: padded), width: 40, height: 12)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let screen = rows(app)
        #expect(screen.contains { $0.contains("ALPHA") }, "the inner one's item: \(screen)")
        #expect(screen.contains { $0.contains("BETA") }, "the outer one's item: \(screen)")
    }

    @Test("In presented content drawn with no window, two .toolbar modifiers on one view keep their items apart")
    func twoToolbarsApartWithNoWindow() {
        // A navigation stack's covered root, the focus-reach probe and a render
        // outside an app all draw with no window chrome; the nesting depth
        // that keeps the two declarations apart was the window's to count, so
        // there both items took one identity — one `@State`, one focus ID.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.presentationHostsToolbar = true
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tuiContext)
        let view = Text("PAGE")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ALPHA") {} } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("BETA") {} } }
        tuiContext.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let screen = renderToBuffer(view, context: context).lines.map(\.stripped)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        #expect(environment.windowChrome == nil, "sanity: no window")
        #expect(screen.contains { $0.contains("ALPHA") }, "sanity: the inner one's row: \(screen)")
        #expect(screen.contains { $0.contains("BETA") }, "sanity: the outer one's row: \(screen)")
        let ids = focusManager.focusableIDs
        #expect(ids.count == 2 && Set(ids).count == 2, "one focus ID each: \(ids)")
    }

    @Test("An item keeps its @State when an `if` before it in the declaration turns")
    func stateSurvivesAConditionalItem() {
        ItemSwitch.shared.on = false
        defer { ItemSwitch.shared.on = false }
        let app = HeadlessApp(ConditionalItemApp(), width: 40, height: 12)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        app.send(KeyEvent(key: .character("c")))
        app.frame(atNanos: 40_000_000)
        app.send(KeyEvent(key: .character("c")))
        app.frame(atNanos: 60_000_000)
        #expect(rows(app).contains { $0.contains("TALLY 2") }, "sanity: \(rows(app))")

        ItemSwitch.shared.on = true
        app.frame(atNanos: 80_000_000)
        app.frame(atNanos: 100_000_000)
        #expect(rows(app).contains { $0.contains("EXTRA") }, "sanity: the conditional item: \(rows(app))")
        #expect(rows(app).contains { $0.contains("TALLY 2") }, "the count stayed with its item: \(rows(app))")

        ItemSwitch.shared.on = false
        app.frame(atNanos: 120_000_000)
        app.frame(atNanos: 140_000_000)
        #expect(rows(app).contains { $0.contains("TALLY 2") }, "and when the `if` turns back: \(rows(app))")
    }
}
