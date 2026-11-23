//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationLifetimeTests.swift
//
//  A toast's life in a running app, on a `TestApp`'s own queue and clock: its
//  action runs once however often it is clicked, and a toast is shown, and
//  goes, whatever happens to what posted it — a window or a sheet that closes,
//  or a burst of toasts too tall for the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// A page that posts a toast with an Undo button as it appears.
private struct UndoPage: View {
    let count: ActionCount
    @Environment(\.notificationService) private var notifications

    var body: some View {
        Text("page").onAppear {
            let count = count
            notifications?.post(
                "Deleted", duration: 30, actions: [NotificationAction("Undo") { count.value.withLock { $0 += 1 } }])
        }
    }
}

private struct UndoApp: App {
    let count: ActionCount
    init() { count = ActionCount() }
    init(_ count: ActionCount) { self.count = count }
    var body: some Scene { WindowGroup { UndoPage(count: count) } }
}

/// The main window: a button that opens the editor.
private struct MainWindowPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let openWindow = openWindow
        Button("open") { openWindow(id: "editor") }
    }
}

/// A second window, whose button posts a toast and closes the window.
private struct EditorPage: View {
    @Environment(\.notificationService) private var notifications
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        // Read at the body, as an action has no environment of its own.
        let (service, dismissWindow) = (notifications, dismissWindow)
        Button("save") {
            service?.post("Saved")
            dismissWindow()
        }
    }
}

private struct TwoWindowsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { MainWindowPage() }
        Window("Editor", id: "editor") { EditorPage() }
    }
}

/// A page that posts ten toasts at once as it appears: more than fit.
private struct BurstPage: View {
    @Environment(\.notificationService) private var notifications

    var body: some View {
        Text("page").onAppear {
            for name in BurstApp.names {
                let message = "Upload of \(name) failed"
                notifications?.post(message, style: .error, duration: 3)
            }
        }
    }
}

private struct BurstApp: App {
    static let names = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]
    init() {}
    var body: some Scene { WindowGroup { BurstPage() } }
}

/// A sheet over the page, and a sheet over that, up from the start.
private struct NestedSheetsPage: View {
    @State private var outer = true

    var body: some View {
        Text("page").sheet(isPresented: $outer) { OuterSheet() }
    }
}

private struct OuterSheet: View {
    @State private var inner = true

    var body: some View {
        Text("outer sheet").sheet(isPresented: $inner) { InnerSheet() }
    }
}

/// The inner sheet: its button posts a toast through the sheet's own service,
/// and closes the sheet.
private struct InnerSheet: View {
    @Environment(\.notificationService) private var notifications
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let (service, dismiss) = (notifications, dismiss)
        Button("remove") {
            service?.post("Removed")
            dismiss()
        }
    }
}

private struct NestedSheetsApp: App {
    init() {}
    var body: some Scene { WindowGroup { NestedSheetsPage() } }
}

// MARK: - Tests

@MainActor
@Suite("A toast's life in a running app")
struct NotificationLifetimeTests {
    @Test("A second click during the fade-out does not run the toast's action again")
    func actionRunsOnce() throws {
        let count = ActionCount()
        let app = TestApp(UndoApp(count), width: 80, height: 12)
        app.advance(by: .milliseconds(500))
        try app.click("Undo")
        app.advance(by: .milliseconds(50))
        #expect(app.screen.contains("Undo"), "still fading out, its button where it was: \(app.screen)")
        try app.click("Undo")
        #expect(count.value.withLock { $0 } == 1)
    }

    @Test("A toast posted from a window that then closes is shown in the window in front, and goes")
    func closedWindowsToast() {
        let app = TestApp(TwoWindowsApp(), width: 80, height: 12)
        _ = app.press(.enter)  // open
        #expect(app.screen.contains("save"), "\(app.screen)")
        _ = app.press(.enter)  // save, and close
        app.advance(by: .milliseconds(500))
        #expect(app.scenes.windows.count == 1)
        #expect(app.screen.contains("Saved"), "drawn in the main window: \(app.screen)")
        app.advance(by: .seconds(10))
        #expect(app.notificationService.entryCount == 0)
    }

    @Test("Toasts that do not fit wait their turn, and every one of a burst is shown")
    func burstAllShown() {
        let app = TestApp(BurstApp(), width: 80, height: 12)
        var seen: Set<String> = []
        for _ in 0..<240 {
            app.advance(by: .milliseconds(250))
            for name in BurstApp.names where app.screen.contains("Upload of \(name) failed") { seen.insert(name) }
        }
        #expect(seen == Set(BurstApp.names), "never shown: \(Set(BurstApp.names).subtracting(seen).sorted())")
        #expect(app.notificationService.entryCount == 0)
    }

    @Test("A toast from a nested sheet that closes is on top of the sheet beneath, and goes")
    func closedNestedSheetsToast() throws {
        let app = TestApp(NestedSheetsApp(), width: 80, height: 16)
        app.advance(by: .milliseconds(500))
        #expect(app.screen.contains("remove"), "\(app.screen)")
        _ = app.press(.enter)  // remove, and close the inner sheet
        app.advance(by: .milliseconds(500))
        #expect(app.screen.contains("outer sheet") && !app.screen.contains("remove"), "\(app.screen)")
        let entry = try #require(app.notificationService.activeEntries().first)
        #expect(!entry.isCovered, "under nothing: the sheet beneath was beneath the one that posted it")
        app.advance(by: .seconds(10))
        #expect(app.screen.contains("outer sheet"))
        #expect(app.notificationService.entryCount == 0)
    }
}
