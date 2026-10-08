//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlLifetimeTests.swift
//
//  An app's objects go with its loop whatever controls it draws (scroll lane
//  review 3, item 5): a control's mouse handler is held by the mouse
//  dispatcher, so a handler that holds the dispatcher back is a cycle, and the
//  dispatcher kept every other handler's objects — the focus manager, the
//  status bar — alive after the loop.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitView

/// An app whose one view is built by `make`, afresh at every frame, as an
/// app's `body` builds its views.
///
/// Not a stored view: a view kept in the app struct is the same instance at
/// every frame, and its `@Environment` box keeps the last frame's environment —
/// whose closures hold the loop that holds the app — which is a cycle of the
/// probe's making, not the control's.
private struct OneViewApp<Content: View>: App {
    let make: @MainActor () -> Content

    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.make = { fatalError("built with init(_:)") } }

    init(_ make: @escaping @MainActor () -> Content) { self.make = make }

    var body: some Scene {
        WindowGroup { make() }
    }
}

@MainActor
@Suite("Controls do not keep the app alive")
struct ControlLifetimeTests {
    private func expectFreed(
        _ comment: String, drawing markers: [String], _ make: @escaping @MainActor () -> some View
    ) {
        AppLifetime.expectFreed(AppLifetime.runAndRelease(OneViewApp(make), drawing: markers), comment)
    }

    @Test("Text alone frees everything (the control)")
    func text() {
        expectFreed("text", drawing: ["hello"]) { Text("hello") }
    }

    /// The review's case: a Button kept the focus manager, the status bar and
    /// the mouse dispatcher. Its mouse handler held the dispatcher that holds
    /// it.
    @Test("A Button, and a ScrollView of them, free the app's objects with their loop")
    func buttons() {
        expectFreed("button", drawing: ["Press"]) { Button("Press") {} }
        expectFreed("scroll view of buttons", drawing: ["item 0"]) {
            ScrollView { ForEach(0..<20, id: \.self) { Button("item \($0)") {} } }
        }
    }

    /// A pop-up menu's trigger action held the focus manager it is registered
    /// with; an inline menu's rows are buttons.
    @Test("A pop-up and an inline Menu free the app's objects with their loop")
    func menus() {
        expectFreed("pop-up menu", drawing: ["Pick"]) { Menu("Pick") { Button("one") {} } }
        expectFreed("pop-up menu with a primary action", drawing: ["Pick"]) {
            Menu("Pick") { Button("one") {} } primaryAction: {}
        }
        expectFreed("inline menu", drawing: ["one"]) { Menu("Pick") { Button("one") {} }.menuStyle(.inline) }
    }

    /// A context menu's Shift+F10 handler held its whole render context, and
    /// with it the key dispatcher that holds the handler; its mouse trigger is
    /// of a `Button`'s shape.
    @Test("A context menu frees the app's objects with its loop")
    func contextMenu() {
        expectFreed("context menu", drawing: ["target"]) { Text("target").contextMenu { Button("Copy") {} } }
    }

    @Test("A menu Picker, a TextField and a draggable free the app's objects with their loop")
    func otherMouseControls() {
        expectFreed("menu picker", drawing: ["Choice"]) {
            Picker("Choice", selection: .constant(1)) {
                Text("first").tag(1)
                Text("second").tag(2)
            }.pickerStyle(.menu)
        }
        expectFreed("text field", drawing: ["field"]) { TextField("Name", text: .constant("field")) }
        expectFreed("draggable", drawing: ["chip"]) { Text("chip").draggable("payload") }
    }
}
