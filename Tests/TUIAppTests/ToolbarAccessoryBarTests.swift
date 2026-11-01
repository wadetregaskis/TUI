//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarAccessoryBarTests.swift
//
//  `.accessoryBar(id:)`: each identifier is a row of the top bar under its
//  items, which the bar modifiers name by the same identifier.
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

extension ToolbarItemPlacement {
    fileprivate static var favorites: Self { accessoryBar(id: "favorites") }
    fileprivate static var tags: Self { accessoryBar(id: "tags") }
}

extension ToolbarPlacement {
    fileprivate static var favorites: Self { accessoryBar(id: "favorites") }
    fileprivate static var tags: Self { accessoryBar(id: "tags") }
}

/// What the probe page states about its bars, reachable from an `App`.
private final class AccessoryProbe: @unchecked Sendable {
    static let shared = AccessoryProbe()
    var favorites: Visibility = .automatic
    var windowToolbar: Visibility = .automatic
    var tagsFill: Color?
}

/// A top bar with an item of its own and two accessory bars.
private struct AccessoryApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .tags) { Text("TAGS") }
                    ToolbarItem(placement: .primaryAction) { Text("TOP") }
                    ToolbarItem(placement: .favorites) { Text("FAV") }
                }
                .toolbarVisibility(AccessoryProbe.shared.favorites, for: .favorites)
                .toolbarVisibility(AccessoryProbe.shared.windowToolbar, for: .windowToolbar)
                .toolbarBackground(AccessoryProbe.shared.tagsFill ?? Color.palette.appHeaderBackground, for: .tags)
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Toolbar accessory bars", .serialized)
struct ToolbarAccessoryBarTests {

    private func reset() {
        AccessoryProbe.shared.favorites = .automatic
        AccessoryProbe.shared.windowToolbar = .automatic
        AccessoryProbe.shared.tagsFill = nil
    }

    /// The raw screen three frames in: one to declare the bars, one to adopt
    /// their rows, one more to settle.
    private func screen() -> [String] {
        let app = TestApp(AccessoryApp(), width: 30, height: 8)
        for frame in 1...3 { app.frame(atNanos: Int64(frame) * 20_000_000) }
        return app.screen.styledLines
    }

    @Test("Each accessory bar is a row under the top bar's own, in the order first declared")
    func rowsUnderTheTopBar() {
        reset()
        defer { reset() }
        let rows = screen().map(\.stripped)
        #expect(rows[0].contains("TOP"), "\(rows)")
        #expect(rows[1].contains("TAGS"), "\(rows)")
        #expect(rows[2].contains("FAV"), "\(rows)")
        #expect(rows[3...].contains { $0.contains("PAGE") }, "the page is under them: \(rows)")
    }

    @Test("Hidden by its own placement, an accessory bar goes, and the rest stay")
    func hidingOne() {
        reset()
        defer { reset() }
        AccessoryProbe.shared.favorites = .hidden
        let rows = screen().map(\.stripped)
        #expect(!rows.contains { $0.contains("FAV") }, "\(rows)")
        #expect(rows[0].contains("TOP") && rows[1].contains("TAGS"), "\(rows)")
    }

    @Test("Hiding the window toolbar leaves its accessory bars")
    func hidingTheWindowToolbar() {
        reset()
        defer { reset() }
        AccessoryProbe.shared.windowToolbar = .hidden
        let rows = screen().map(\.stripped)
        #expect(!rows.contains { $0.contains("TOP") }, "\(rows)")
        #expect(rows[0].contains("TAGS") && rows[1].contains("FAV"), "\(rows)")
    }

    @Test("A fill stated for an accessory bar fills its row, and only it")
    func fillingOne() {
        reset()
        defer { reset() }
        AccessoryProbe.shared.tagsFill = .rgb(0, 200, 0)
        let rows = screen()
        let green = ANSIRenderer.backgroundCode(for: .rgb(0, 200, 0))
        #expect(rows[1].stripped.contains("TAGS") && rows[1].contains(green), "\(rows)")
        #expect(!rows[0].contains(green) && !rows[2].contains(green), "\(rows)")
    }
}
