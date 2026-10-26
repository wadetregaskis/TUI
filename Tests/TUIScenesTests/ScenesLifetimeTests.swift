//  🖥️ TUI — A Terminal UI framework for Swift
//  ScenesLifetimeTests.swift
//
//  An app of several scenes frees its objects with its loop: the scene
//  presenter holds the app's windows, their bars and the scenes' views, and the
//  environment every view keeps a copy of reaches it — weakly, or the copies a
//  key handler or a focus registration keep would close a cycle.
//
//  The buttons' actions capture nothing of their views: a view with an
//  `@Environment` whose shortcut's action captures it keeps its whole
//  environment in the shortcut registry, a cycle with one window as with
//  several (`EnvironmentBox` keeps the environment it was resolved in).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
@testable import TUIScenes

// MARK: - Fixtures

/// Opens the other window as it appears, so the second frame draws two.
private struct OpeningPage: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isOn = false

    var body: some View {
        VStack {
            Text("main page")
            Toggle("Switch", isOn: $isOn)
            Button("Press") {}.keyboardShortcut("p")
        }
        .onAppear { openWindow(id: "other") }
    }
}

private struct OtherPage: View {
    @State private var isOn = true

    var body: some View {
        VStack {
            Text("other page")
            Toggle("Other switch", isOn: $isOn)
            Button("Other press") {}.keyboardShortcut("o")
        }
    }
}

private struct ScenesLifetimeApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { OpeningPage() }
        Window("Other", id: "other") { OtherPage() }
        Settings { Text("settings") }
        AlertScene("Lifetime", isPresented: .constant(false)) {}
    }
}

// MARK: - Tests

@MainActor
@Suite("Several scenes do not keep the app alive")
struct ScenesLifetimeTests {
    @Test("An app of several scenes, two windows open, frees its objects with its loop")
    func scenesFreed() {
        let probes = AppLifetime.runAndRelease(ScenesLifetimeApp(), drawing: ["Other switch"])
        AppLifetime.expectFreed(probes, "several scenes")
    }
}
