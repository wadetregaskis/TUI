//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarKeyboardPlacementTests.swift
//
//  `.keyboard` items are in the bottom bar, at its leading end, while a text
//  input inside the view that declared them has the focus — and nowhere
//  otherwise.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
import TUITextInput

/// Whether the probe's field is inside the view that declares the keyboard
/// item, reachable from an `App`.
private final class KeyboardProbe: @unchecked Sendable {
    static let shared = KeyboardProbe()
    var fieldInside = true
}

/// A field and a button, with a keyboard item declared round the field (or
/// round the button alone).
private struct KeyboardApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { KeyboardPage() }
            .windowToolbarStyle(.unifiedCompact)
    }
}

private struct KeyboardPage: View {
    @State private var name = ""

    var body: some View {
        if KeyboardProbe.shared.fieldInside {
            VStack {
                TextField("NAME", text: $name)
                Button("OTHER") {}
            }
            .toolbar { ToolbarItem(placement: .keyboard) { Text("KBD") } }
        } else {
            VStack {
                TextField("NAME", text: $name)
                VStack { Button("OTHER") {} }
                    .toolbar { ToolbarItem(placement: .keyboard) { Text("KBD") } }
            }
        }
    }
}

@MainActor
@Suite("Toolbar keyboard placement", .serialized)
struct ToolbarKeyboardPlacementTests {

    /// The app after `frames` frames.
    private func frames(_ app: HeadlessApp, _ count: Int, from start: inout Int64) -> [String] {
        for _ in 0..<count {
            start += 20_000_000
            app.frame(atNanos: start)
        }
        return app.screen.map(\.stripped)
    }

    @Test("While the declaring view's field has the focus, the item is at the bottom bar's leading end")
    func shownWhileTyping() {
        KeyboardProbe.shared.fieldInside = true
        let app = HeadlessApp(KeyboardApp(), width: 30, height: 8)
        var now: Int64 = 0
        let rows = frames(app, 3, from: &now)
        #expect(app.focusedID?.contains("textfield") == true, "the field takes the first focus: \(String(describing: app.focusedID))")
        #expect(rows.last?.hasPrefix("KBD") == true, "\(rows)")

        // Tab to the button: no typing, so no keyboard item, a frame later.
        _ = app.send(KeyEvent(key: .tab))
        let after = frames(app, 3, from: &now)
        #expect(!after.contains { $0.contains("KBD") }, "\(after)")
    }

    @Test("A field outside the declaring view does not show it")
    func notForAFieldOutside() {
        KeyboardProbe.shared.fieldInside = false
        defer { KeyboardProbe.shared.fieldInside = true }
        let app = HeadlessApp(KeyboardApp(), width: 30, height: 8)
        var now: Int64 = 0
        let rows = frames(app, 3, from: &now)
        #expect(app.focusedID?.contains("textfield") == true)
        #expect(!rows.contains { $0.contains("KBD") }, "\(rows)")
    }
}
