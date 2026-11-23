//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneRootLanguageTests.swift
//
//  The app's language is the root `\.locale` of its scene (the owner's
//  A-APPSTATE-1, 2026-10-28): words read in the app's work where no view is
//  drawing — a title read at an init, the bars' labels, undo titles — follow
//  `WindowGroup { … }.environment(\.locale, …)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStrings
import TUITesting
@testable import TUITestSupport

/// A page that reads one of TUI's words as the bars read theirs: in its body,
/// through the service, with no locale in hand.
private struct ServiceWordPage: View {
    var body: some View {
        Text(verbatim: "[" + LocalizationService.shared.string(for: LocalizationKey.Button.cancel) + "]")
    }
}

private struct GermanRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { ServiceWordPage() }
            .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

/// A scroll view taller than the screen, its "N more" lines drawn as words.
private struct GermanRootScrollApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<40, id: \.self) { Text(verbatim: "line \($0)") }
                }
            }
            .scrollIndicatorStyle(.text)
            .scrollIndicatorPlacement(.besideContent)
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

private struct UnstatedRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { ServiceWordPage() }
    }
}

@MainActor
@Suite("The app's language is its scene's root locale", .rendersEnglishUI)
struct SceneRootLanguageTests {
    private func word(_ app: some App) -> String {
        let app = TestApp(app, width: 40, height: 4)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let screen = app.screen.lines.joined(separator: "\n")
        guard let open = screen.firstIndex(of: "["), let close = screen[open...].firstIndex(of: "]") else { return screen }
        return String(screen[screen.index(after: open)..<close])
    }

    @Test("A word read with no locale in hand follows the scene's root locale")
    func rootLocaleReachesTheService() {
        #expect(word(GermanRootApp()) == "Abbrechen")
    }

    @Test("A scroll view's 'N more' line is in the scene's language")
    func scrollIndicatorWords() {
        let app = TestApp(GermanRootScrollApp(), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let screen = app.screen.lines.joined(separator: "\n")
        #expect(screen.contains("weitere Zeilen unten"), "\(screen)")
        #expect(!screen.contains("more") && !screen.contains("lines below"), "\(screen)")
    }

    @Test("A scene that states no locale reads the process's language")
    func unstated() {
        #expect(word(UnstatedRootApp()) == "Cancel")
    }

    @Test("Outside the app's work the process's language stands")
    func outsideTheApp() {
        _ = word(GermanRootApp())
        #expect(LocalizationService.shared.string(for: LocalizationKey.Button.cancel) == "Cancel")
    }
}
