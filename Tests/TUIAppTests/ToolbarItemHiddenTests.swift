//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarItemHiddenTests.swift
//
//  `.toolbarItemHidden(_:)` hides one view of a toolbar item, which closes up
//  round it, and changes nothing outside a toolbar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// Whether the probe hides its views, reachable from an `App`.
private final class Hiding: @unchecked Sendable {
    static let shared = Hiding()
    var hidden = true
}

/// A top bar group of three views, the middle one hidden as `Hiding` says, and
/// the same three on the page.
private struct HiddenItemApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            HStack(spacing: 1) {
                Text("PA")
                Text("PB").toolbarItemHidden(Hiding.shared.hidden)
                Text("PC")
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Text("TA")
                    Text("TB").toolbarItemHidden(Hiding.shared.hidden)
                    Text("TC")
                }
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Toolbar item hidden", .serialized)
struct ToolbarItemHiddenTests {

    /// The screen, two frames in: one to declare the bar, one to draw it.
    private func screen() -> [String] {
        let app = TestApp(HiddenItemApp(), width: 30, height: 5)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen.lines
    }

    @Test("A hidden view of a toolbar item takes no room, and the item closes up round it")
    func hidesWithinTheItem() {
        Hiding.shared.hidden = true
        defer { Hiding.shared.hidden = true }
        let rows = screen()
        #expect(rows.first?.hasSuffix("TA TC") == true, "\(rows)")
        #expect(!(rows.first?.contains("TB") ?? true), "\(rows)")
        Hiding.shared.hidden = false
        #expect(screen().first?.hasSuffix("TA TB TC") == true)
    }

    @Test("Outside a toolbar it changes nothing")
    func outsideAToolbar() {
        Hiding.shared.hidden = true
        let rows = screen()
        #expect(rows.contains { $0.contains("PA PB PC") }, "\(rows)")
    }
}
