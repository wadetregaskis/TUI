//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowDismissBehaviorTests.swift
//
//  `DismissBehavior` (decisions A22, with lane O9): under the default,
//  interactive behavior, `dismissWindow` leaves a window that is showing a
//  sheet open — the window in front or one held behind it — and under
//  `withTransaction(\.dismissBehavior, .destructive)` it closes it anyway.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
import TUIkitPresentation

// MARK: - Fixtures

/// The window in front, which presents a sheet that tries to close it.
private struct SheetWindowPage: View {
    @State private var showsSheet = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("present") { showsSheet = true }
            .sheet(isPresented: $showsSheet) {
                VStack {
                    Text("sheet up")
                    Button("interactive") { dismissWindow() }
                    Button("destructive") {
                        withTransaction(\.dismissBehavior, .destructive) { dismissWindow() }
                    }
                }
            }
    }
}

/// The main window, which presents a sheet that opens the other window over
/// it.
private struct MainSheetPage: View {
    @State private var showsSheet = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("present") { showsSheet = true }
            .sheet(isPresented: $showsSheet) {
                Button("open other") { openWindow(id: "other") }
            }
    }
}

/// The other window, which tries to close the main one behind it.
private struct ClosingPage: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack {
            Text("other window")
            Button("interactive") { dismissWindow(id: "main") }
            Button("destructive") {
                withTransaction(\.dismissBehavior, .destructive) { dismissWindow(id: "main") }
            }
        }
    }
}

private struct BehaviorApp: App {
    init() {}
    var body: some Scene {
        WindowGroup(id: "main") { MainSheetPage() }
        Window("Front", id: "front") { SheetWindowPage() }
        Window("Other", id: "other") { ClosingPage() }
    }
}

// MARK: - Tests

@MainActor
@Suite("Window dismissal behaviors", .serialized)
struct WindowDismissBehaviorTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp<BehaviorApp>) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func press(_ key: Key, in app: HeadlessApp<BehaviorApp>) {
        app.send(KeyEvent(key: key))
        frame(app)
    }

    private func screen(_ app: HeadlessApp<BehaviorApp>) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    @Test("A transaction's dismiss behavior is interactive unless set")
    func transactionDefault() {
        var transaction = Transaction()
        #expect(transaction.dismissBehavior == .interactive)
        transaction.dismissBehavior = .destructive
        #expect(transaction.dismissBehavior == .destructive)
        transaction.dismissBehavior = .interactive
        #expect(transaction.dismissBehavior == .interactive)
    }

    @Test("Interactive leaves the window in front open while it shows a sheet; destructive closes it")
    mutating func frontWindowWithSheet() {
        let app = HeadlessApp(BehaviorApp(), width: 50, height: 12)
        frame(app)
        app.scenes.open(WindowTarget(id: "front"))
        frame(app)
        press(.enter, in: app)  // present
        #expect(screen(app).contains("sheet up"))
        press(.enter, in: app)  // interactive
        #expect(app.scenes.windows.count == 2, "a window showing a sheet stays open")
        press(.tab, in: app)
        press(.enter, in: app)  // destructive
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
    }

    @Test("Interactive leaves a window held behind open while it shows a sheet; destructive closes it")
    mutating func heldWindowWithSheet() {
        let app = HeadlessApp(BehaviorApp(), width: 50, height: 12)
        frame(app)
        press(.enter, in: app)  // present
        press(.enter, in: app)  // open other
        #expect(screen(app).contains("other window"))
        press(.enter, in: app)  // interactive
        #expect(app.scenes.windows.count == 2, "the main window shows a sheet behind this one")
        press(.tab, in: app)
        press(.enter, in: app)  // destructive
        #expect(app.scenes.windows.count == 1)
        #expect(screen(app).contains("other window"))
    }
}
