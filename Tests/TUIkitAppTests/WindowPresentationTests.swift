//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowPresentationTests.swift
//
//  Several windows on one surface (refusal review O9, ruled (b)): `openWindow`
//  opens a window over the whole terminal, in front of the one open; Escape,
//  `dismissWindow` and `dismiss()` at its root close it and the window behind
//  comes back as it was left — its state, its focus, its bars; a `Window`
//  opens once and a `WindowGroup` each time; the last window closing quits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation

// MARK: - Fixtures

/// What the windows' views did, reachable from an `App`.
private final class WindowsProbe: @unchecked Sendable {
    static let shared = WindowsProbe()
    var log: [String] = []
}

/// The main window: a counter, and buttons that open the other windows.
private struct MainPage: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var count = 0

    var body: some View {
        VStack {
            Text("main count=\(count) multiple=\(supportsMultipleWindows)")
            Button("bump") { count += 1 }
            Button("inspect") { openWindow(id: "inspector") }
            Button("view") { openWindow(id: "viewer") }
            Button("nowhere") { openWindow(id: "no-such-scene") }
        }
        .toolbar { ToolbarItem(placement: .navigation) { Text("MAIN-BAR") } }
        .onDisappear { WindowsProbe.shared.log.append("main disappeared") }
    }
}

/// The `Window` scene's content, with its ways out.
private struct InspectorPage: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("inspector")
            Button("dismiss-window") { dismissWindow() }
            Button("dismiss") { dismiss() }
            Button("close-viewers") { dismissWindow(id: "viewer") }
        }
        .toolbar { ToolbarItem(placement: .navigation) { Text("INSPECTOR-BAR") } }
        .onAppear { WindowsProbe.shared.log.append("inspector appeared") }
        .onDisappear { WindowsProbe.shared.log.append("inspector disappeared") }
    }
}

/// A window group's content, with a counter of its own.
private struct ViewerPage: View {
    @State private var count = 0

    var body: some View {
        Button("viewer count=\(count)") { count += 1 }
    }
}

private struct WindowsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { MainPage() }
        Window("Inspector", id: "inspector") { InspectorPage() }
        WindowGroup("Viewer", id: "viewer") { ViewerPage() }
    }
}

/// A `Window` first: the window opened at launch.
private struct WindowFirstApp: App {
    init() {}
    var body: some Scene {
        Window("Solo", id: "solo") { Text("solo window") }
        WindowGroup { Text("never opened") }
    }
}

// MARK: - Tests

@MainActor
@Suite("Windows on one surface", .serialized)
struct WindowPresentationTests {
    private var now: Int64 = 0

    /// `app` after its first two frames, its log cleared.
    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        WindowsProbe.shared.log = []
        let headless = HeadlessApp(app, width: 50, height: 12)
        frame(headless)
        frame(headless)
        return headless
    }

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func screen<A: App>(_ app: HeadlessApp<A>) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    /// Presses `key` and draws a frame.
    private mutating func press<A: App>(_ key: Key, in app: HeadlessApp<A>) {
        app.send(KeyEvent(key: key))
        frame(app)
    }

    /// Tabs `tabs` times from the first control and presses Return there.
    private mutating func choose<A: App>(tabs: Int, in app: HeadlessApp<A>) {
        for _ in 0..<tabs { press(.tab, in: app) }
        press(.enter, in: app)
        frame(app)
    }

    @Test("openWindow opens the Window scene over the whole surface; the main window is not drawn")
    mutating func openWindowCovers() {
        let app = launched(WindowsApp())
        #expect(screen(app).contains("main count=0 multiple=true"))
        choose(tabs: 1, in: app)
        let text = screen(app)
        #expect(text.contains("inspector"), "\(text)")
        #expect(!text.contains("main count"), "\(text)")
        #expect(app.scenes.windows.count == 2)
    }

    @Test("Escape closes the window in front, and the main window comes back with its state")
    mutating func escapeClosesAndStateSurvives() {
        let app = launched(WindowsApp())
        press(.enter, in: app)  // bump
        press(.enter, in: app)  // bump
        #expect(screen(app).contains("main count=2"))
        choose(tabs: 1, in: app)
        #expect(screen(app).contains("inspector"))
        press(.escape, in: app)
        frame(app)
        let text = screen(app)
        #expect(text.contains("main count=2"), "\(text)")
        #expect(app.scenes.windows.count == 1)
        #expect(app.quitsRequested == 0)
    }

    @Test("A window held behind another does not disappear; one closed does")
    mutating func lifecycleOfHeldAndClosedWindows() {
        let app = launched(WindowsApp())
        choose(tabs: 1, in: app)
        #expect(WindowsProbe.shared.log == ["inspector appeared"], "\(WindowsProbe.shared.log)")
        press(.escape, in: app)
        frame(app)
        #expect(WindowsProbe.shared.log == ["inspector appeared", "inspector disappeared"], "\(WindowsProbe.shared.log)")
    }

    @Test("The focus comes back to the control that opened the window")
    mutating func focusReturns() {
        let app = launched(WindowsApp())
        choose(tabs: 2, in: app)  // view
        #expect(screen(app).contains("viewer count=0"))
        press(.escape, in: app)
        frame(app)
        press(.enter, in: app)  // the focus is on "view" again: a viewer opens
        frame(app)
        #expect(screen(app).contains("viewer count=0"), "\(screen(app))")
    }

    @Test("Each window has its own bars: the window in front's toolbar, and the main window's again after")
    mutating func ownBars() {
        let app = launched(WindowsApp())
        #expect(screen(app).contains("MAIN-BAR"))
        choose(tabs: 1, in: app)
        frame(app)
        let inspecting = screen(app)
        #expect(inspecting.contains("INSPECTOR-BAR") && !inspecting.contains("MAIN-BAR"), "\(inspecting)")
        press(.escape, in: app)
        let back = screen(app)
        #expect(back.contains("MAIN-BAR") && !back.contains("INSPECTOR-BAR"), "\(back)")
    }

    @Test("A Window opens one window: opening it again brings that one to the front")
    mutating func windowOpensOnce() {
        let app = launched(WindowsApp())
        app.scenes.open(WindowTarget(id: "inspector"))
        app.scenes.open(WindowTarget(id: "viewer"))
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        #expect(app.scenes.windows.count == 3)
        #expect(screen(app).contains("inspector"))
    }

    @Test("A WindowGroup opens a new window each time, each with its own state")
    mutating func groupOpensEachTime() {
        let app = launched(WindowsApp())
        choose(tabs: 2, in: app)  // view
        press(.enter, in: app)  // the viewer's button
        #expect(screen(app).contains("viewer count=1"))
        app.scenes.open(WindowTarget(id: "viewer"))
        frame(app)
        frame(app)
        #expect(app.scenes.windows.count == 3)
        #expect(screen(app).contains("viewer count=0"), "a second viewer, of its own state: \(screen(app))")
        press(.escape, in: app)
        frame(app)
        #expect(screen(app).contains("viewer count=1"), "the first, as it was: \(screen(app))")
    }

    @Test("An identifier no scene declares opens nothing")
    mutating func unknownIdentifier() {
        let app = launched(WindowsApp())
        choose(tabs: 3, in: app)
        #expect(app.scenes.windows.count == 1)
        #expect(screen(app).contains("main count=0"))
    }

    @Test("dismissWindow() in a window closes it")
    mutating func dismissWindowCloses() {
        let app = launched(WindowsApp())
        choose(tabs: 1, in: app)
        choose(tabs: 0, in: app)  // dismiss-window
        #expect(app.scenes.windows.count == 1)
        #expect(screen(app).contains("main count=0"))
        #expect(app.quitsRequested == 0)
    }

    @Test("dismiss() at a window's root closes the window, not the app")
    mutating func dismissAtRootCloses() {
        let app = launched(WindowsApp())
        choose(tabs: 1, in: app)
        choose(tabs: 1, in: app)  // dismiss
        #expect(app.scenes.windows.count == 1)
        #expect(app.quitsRequested == 0)
    }

    @Test("dismissWindow(id:) closes every open window of that scene")
    mutating func dismissWindowByIdentifier() {
        let app = launched(WindowsApp())
        app.scenes.open(WindowTarget(id: "viewer"))
        app.scenes.open(WindowTarget(id: "viewer"))
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        frame(app)
        choose(tabs: 2, in: app)  // close-viewers
        #expect(app.scenes.windows.count == 2)
        #expect(screen(app).contains("inspector"))
    }

    @Test("The last window closing quits the app")
    mutating func lastWindowQuits() {
        let app = launched(WindowFirstApp())
        #expect(screen(app).contains("solo window"))
        app.scenes.dismiss(.current(app.scenes.windows[0].serial))
        frame(app)
        #expect(app.quitsRequested == 1)
        #expect(app.scenes.windows.isEmpty)
    }

    @Test("A Window first in the body is the window opened at launch")
    mutating func windowFirstOpensAtLaunch() {
        let text = screen(launched(WindowFirstApp()))
        #expect(text.contains("solo window") && !text.contains("never opened"), "\(text)")
    }
}
