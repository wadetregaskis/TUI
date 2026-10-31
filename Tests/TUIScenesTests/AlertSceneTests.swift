//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertSceneTests.swift
//
//  `AlertScene` (lane O9) and the scene-level dialog modifiers (decisions
//  A26): an alert that is a scene of its own, presented over the window in
//  front while its binding is true, its dialog modifiers reaching it and not
//  the window's own alerts; and the modifiers on a window scene reaching the
//  alerts its views present.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUIScenes

// MARK: - Fixtures

/// The scene's binding and what its actions did, reachable from an `App`.
private final class AlertProbe: @unchecked Sendable {
    static let shared = AlertProbe()
    var isPresented = false
    var isSuppressed = false
    var pageAlert = false
    var log: [String] = []

    var binding: Binding<Bool> {
        Binding(get: { Self.shared.isPresented }, set: { Self.shared.isPresented = $0 })
    }
}

/// A window with an alert of its own.
private struct PageWithAlert: View {
    var body: some View {
        Text("main window")
            .alert(
                "Page Alert",
                isPresented: Binding(get: { AlertProbe.shared.pageAlert }, set: { AlertProbe.shared.pageAlert = $0 })
            ) {
                Button("Fine") {}
            }
    }
}

private struct AlertSceneApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { PageWithAlert() }
        AlertScene("Login Required", isPresented: AlertProbe.shared.binding) {
            Button("Sign In") { AlertProbe.shared.log.append("sign in") }
            Button("Later", role: .cancel) { AlertProbe.shared.log.append("later") }
        } message: {
            Text("Your session ended.")
        }
        .dialogSeverity(.critical)
        .dialogSuppressionToggle(
            "Never ask",
            isSuppressed: Binding(get: { AlertProbe.shared.isSuppressed }, set: { AlertProbe.shared.isSuppressed = $0 }))
    }
}

private struct NoActionsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        AlertScene("Heads Up", isPresented: AlertProbe.shared.binding) {}
    }
}

private struct PresentingNilApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        AlertScene("About", isPresented: AlertProbe.shared.binding, presenting: String?.none) { name in
            Button(name) {}
        }
    }
}

/// The dialog modifiers on the window scene, reaching its views' alerts.
private struct WindowSeverityApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { PageWithAlert() }
            .dialogSeverity(.critical)
    }
}

// MARK: - Tests

@MainActor
@Suite("Alert scenes", .serialized)
struct AlertSceneTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func screen(_ app: HeadlessApp) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    private mutating func launched<A: App>(_ app: A, presented: Bool = true) -> HeadlessApp {
        AlertProbe.shared.isPresented = presented
        AlertProbe.shared.isSuppressed = false
        AlertProbe.shared.pageAlert = false
        AlertProbe.shared.log = []
        let headless = HeadlessApp(app, width: 60, height: 16)
        frame(headless)
        return headless
    }

    @Test("While its binding is true, the alert is presented over the window, with its message")
    mutating func presented() {
        let app = launched(AlertSceneApp())
        let text = screen(app)
        #expect(text.contains("Login Required") && text.contains("Your session ended."), "\(text)")
        #expect(text.contains("Sign In") && text.contains("Later"), "\(text)")
    }

    @Test("Choosing an action runs it and dismisses the alert, setting the binding false")
    mutating func actionDismisses() {
        let app = launched(AlertSceneApp())
        app.send(KeyEvent(key: .escape))
        frame(app)
        #expect(AlertProbe.shared.log == ["later"])
        #expect(!AlertProbe.shared.isPresented)
        #expect(!screen(app).contains("Login Required"))
    }

    @Test("Not presented, nothing is drawn")
    mutating func notPresented() {
        let app = launched(AlertSceneApp(), presented: false)
        #expect(!screen(app).contains("Login Required"))
    }

    @Test("The scene's dialog modifiers reach its alert: critical, and a suppression checkbox")
    mutating func sceneModifiersReachTheAlert() {
        let app = launched(AlertSceneApp())
        let text = screen(app)
        #expect(text.hasCautionSign, "a critical alert's caution sign: \(text)")
        #expect(text.contains("Never ask"), "\(text)")
    }

    @Test("The alert scene's modifiers do not reach the window's own alerts")
    mutating func sceneModifiersStayWithTheirAlert() {
        let app = launched(AlertSceneApp(), presented: false)
        AlertProbe.shared.pageAlert = true
        frame(app)
        let text = screen(app)
        #expect(text.contains("Page Alert"), "\(text)")
        #expect(!text.hasCautionSign && !text.contains("Never ask"), "\(text)")
    }

    @Test("A window scene's dialog severity reaches the alerts its views present")
    mutating func windowSceneSeverity() {
        let app = launched(WindowSeverityApp(), presented: false)
        AlertProbe.shared.pageAlert = true
        frame(app)
        #expect(screen(app).hasCautionSign, "\(screen(app))")
    }

    @Test("With no actions, the alert has an OK button")
    mutating func noActionsHasOK() {
        let app = launched(NoActionsApp())
        #expect(screen(app).contains("Heads Up") && screen(app).contains("OK"), "\(screen(app))")
    }

    @Test("Presenting nil presents nothing, whatever the binding says")
    mutating func presentingNil() {
        let app = launched(PresentingNilApp())
        #expect(!screen(app).contains("About"), "\(screen(app))")
    }
}

extension String {
    /// Whether a critical dialog's caution sign, U+26A0, is drawn here — in
    /// whichever presentation the terminal is given it (`⚠️` is one character
    /// with its variation selector, which `contains("⚠")` does not match).
    fileprivate var hasCautionSign: Bool {
        unicodeScalars.contains("\u{26A0}")
    }
}
