//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowPresentedDataTests.swift
//
//  A window group that presents data (`WindowGroup(for:)`): each window
//  presents its own value through a binding, `openWindow(value:)` opens one
//  for a value or brings the window presenting it to the front, and
//  `dismissWindow(value:)` closes that window alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

/// A window presenting a note's number, which its button moves on.
private struct NoteView: View {
    @Binding var number: Int?

    var body: some View {
        Button("note \(number.map(String.init) ?? "none")") { number = (number ?? 0) + 100 }
    }
}

/// A window presenting a count that has a default.
private struct CountView: View {
    @Binding var count: Int

    var body: some View {
        Button("count \(count)") { count += 1 }
    }
}

private struct ValuedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        WindowGroup("Note", for: Int.self) { $number in NoteView(number: $number) }
        WindowGroup(id: "counter", for: Int.self) { $count in CountView(count: $count) } defaultValue: { 10 }
    }
}

// MARK: - Tests

@MainActor
@Suite("Windows that present data", .serialized)
struct WindowPresentedDataTests {
    private var now: Int64 = 0

    private mutating func launched() -> HeadlessApp {
        let app = HeadlessApp(ValuedApp(), width: 40, height: 8)
        frame(app)
        return app
    }

    private mutating func frame(_ app: HeadlessApp) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func screen(_ app: HeadlessApp) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    private func open(_ app: HeadlessApp) -> OpenWindowAction {
        OpenWindowAction(handler: app.scenes.actions)
    }

    @Test("openWindow(value:) opens a window of the group presenting that type, presenting the value")
    mutating func opensForValue() {
        let app = launched()
        open(app)(value: 3)
        frame(app)
        #expect(screen(app).contains("note 3"), "\(screen(app))")
        #expect(app.scenes.windows.count == 2)
    }

    @Test("Opening a value a window presents brings that window to the front; another value opens another")
    mutating func sameValueFrontsIt() {
        let app = launched()
        open(app)(value: 3)
        frame(app)
        open(app)(value: 4)
        frame(app)
        #expect(screen(app).contains("note 4"))
        open(app)(value: 3)
        frame(app)
        #expect(screen(app).contains("note 3"), "\(screen(app))")
        #expect(app.scenes.windows.count == 3)
    }

    @Test("A write through the binding changes what the window presents, which openWindow finds it by")
    mutating func bindingWriteMovesTheValue() {
        let app = launched()
        open(app)(value: 3)
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        #expect(screen(app).contains("note 103"), "\(screen(app))")
        open(app)(value: 9)
        frame(app)
        open(app)(value: 103)
        frame(app)
        #expect(screen(app).contains("note 103"))
        #expect(app.scenes.windows.count == 3, "103 is the first note window's value now: it came to the front")
    }

    @Test("dismissWindow(value:) closes the window presenting that value alone")
    mutating func dismissByValue() {
        let app = launched()
        open(app)(value: 3)
        open(app)(value: 4)
        frame(app)
        DismissWindowAction(handler: app.scenes.actions, window: nil)(value: 4)
        frame(app)
        #expect(app.scenes.windows.count == 2)
        #expect(screen(app).contains("note 3"), "\(screen(app))")
    }

    @Test("A group with a default value presents it when opened by identifier; id and value pick the group")
    mutating func defaultValueAndIdentifier() {
        let app = launched()
        open(app)(id: "counter")
        frame(app)
        #expect(screen(app).contains("count 10"), "\(screen(app))")
        open(app)(id: "counter", value: 5)
        frame(app)
        #expect(screen(app).contains("count 5"), "\(screen(app))")
        DismissWindowAction(handler: app.scenes.actions, window: nil)(id: "counter", value: 5)
        frame(app)
        #expect(screen(app).contains("count 10"))
    }

    @Test("A window group's window opened by its identifier with no value presents nil")
    mutating func noValueIsNil() {
        let app = launched()
        #expect(app.scenes.open(WindowTarget(id: nil, value: nil, valueType: Int.self)))
        frame(app)
        #expect(screen(app).contains("note none"), "\(screen(app))")
    }

    @Test("Sharing: requested opens the window, required throws and opens nothing, as no window is ever shared")
    mutating func sharingBehavior() async {
        let app = launched()
        await #expect(throws: Never.self) { try await open(app)(value: 3, sharingBehavior: OpenWindowAction.SharingBehavior.requested) }
        #expect(app.scenes.windows.count == 2)
        await #expect(throws: (any Error).self) { try await open(app)(value: 4, sharingBehavior: OpenWindowAction.SharingBehavior.required) }
        #expect(app.scenes.windows.count == 2)
        await #expect(throws: (any Error).self) { try await open(app)(id: "no-such-scene", sharingBehavior: OpenWindowAction.SharingBehavior.requested) }
    }
}
