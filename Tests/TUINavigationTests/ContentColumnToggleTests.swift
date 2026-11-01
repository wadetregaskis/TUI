//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentColumnToggleTests.swift
//
//  A three-column split view's top bar shows two buttons — the sidebar's and,
//  beside it, the content column's — coupled so that no pair of presses leaves
//  the sidebar showing with no content column after it (owner, 2026-10-16).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUINavigation
import TUITesting
@testable import TUITestSupport

/// A split view's column visibility, by reference so the binding a frame built
/// reaches it. Each app has its own, so suites running side by side share
/// nothing.
private final class Visibility: @unchecked Sendable {
    var value: NavigationSplitViewVisibility
    init(_ value: NavigationSplitViewVisibility) { self.value = value }
    var binding: Binding<NavigationSplitViewVisibility> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

private struct ThreeColumns: View {
    let visibility: Visibility
    var removesContentButton = false

    var body: some View {
        let split = NavigationSplitView(columnVisibility: visibility.binding) {
            Text("SIDE")
        } content: {
            Text("LIST")
        } detail: {
            Text("DETAIL")
        }
        .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        if removesContentButton {
            split.toolbar(removing: .contentColumnToggle)
        } else {
            split
        }
    }
}

private struct ThreeColumnApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { ThreeColumns(visibility: Self.visibility) } }
}

private struct ShownApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { ThreeColumns(visibility: Self.visibility) } }
}

private struct DetailOnlyApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { ThreeColumns(visibility: Self.visibility) } }
}

private struct RemovedContentButtonApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene {
        WindowGroup { ThreeColumns(visibility: Self.visibility, removesContentButton: true) }
    }
}

private struct TwoColumnApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene {
        WindowGroup {
            NavigationSplitView(columnVisibility: Self.visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL")
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

@MainActor
@Suite("A three-column split view's content-column button", .rendersEnglishUI)
struct ContentColumnToggleTests {
    private func running<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 60, height: 12)
        for index in 1...5 { headless.frame(atNanos: Int64(index) * 16_666_667) }
        return headless
    }

    private func rows(_ app: TestApp) -> [String] {
        app.screen.lines
    }

    /// The top bar's buttons, by their arrows, leading first.
    private func barArrows(_ app: TestApp) -> [Character] {
        guard let bar = rows(app).first(where: { $0.contains("ITEM") }) else { return [] }
        return bar.prefix { $0 != "I" }.filter { $0 == "◀" || $0 == "▶" }
    }

    /// Clicks the `ordinal`th arrow of the top bar, and draws what follows.
    private func clickArrow(_ app: TestApp, _ ordinal: Int) throws {
        let screen = rows(app)
        let row = try #require(screen.firstIndex { $0.contains("ITEM") }, "\(screen)")
        let line = screen[row]
        let columns = line.indices.filter { line[$0] == "◀" || line[$0] == "▶" }
        let column = try #require(ordinal < columns.count ? columns[ordinal] : nil, "\(line)")
        let x = line.distance(from: line.startIndex, to: column)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: x, y: row))
        for index in 6...8 { app.frame(atNanos: Int64(index) * 16_666_667) }
    }

    @Test("The top bar shows the sidebar's button and the content column's, each in its column's state")
    func twoButtons() {
        ShownApp.visibility.value = .all
        let app = running(ShownApp())
        #expect(barArrows(app) == ["◀", "◀"], "\(rows(app))")
    }

    @Test("The content button closes the content column and the sidebar with it")
    func contentClosesBoth() throws {
        ThreeColumnApp.visibility.value = .all
        let app = running(ThreeColumnApp())
        try clickArrow(app, 1)
        #expect(ThreeColumnApp.visibility.value == .detailOnly)
        #expect(barArrows(app) == ["▶", "▶"], "\(rows(app))")
    }

    @Test("From detail alone, the content button opens the content column, the sidebar's opens both")
    func reopening() throws {
        DetailOnlyApp.visibility.value = .detailOnly
        let app = running(DetailOnlyApp())
        try clickArrow(app, 1)
        #expect(DetailOnlyApp.visibility.value == .doubleColumn)
        DetailOnlyApp.visibility.value = .detailOnly
        for index in 9...11 { app.frame(atNanos: Int64(index) * 16_666_667) }
        try clickArrow(app, 0)
        #expect(DetailOnlyApp.visibility.value == .all)
    }

    @Test("No two presses leave the sidebar showing without the content column")
    func neverSidebarAlone() {
        let states: [NavigationSplitViewVisibility] = [.all, .doubleColumn, .detailOnly]
        for start in states {
            for next in [
                SplitViewToggle.togglingSidebar(start, isThreeColumn: true),
                SplitViewToggle.togglingContent(start, isThreeColumn: true) ?? start,
            ] {
                #expect(states.contains(next), "\(start) → \(next)")
            }
        }
    }

    @Test("toolbar(removing: .contentColumnToggle) takes the content button and leaves the sidebar's")
    func removal() {
        RemovedContentButtonApp.visibility.value = .all
        let app = running(RemovedContentButtonApp())
        #expect(barArrows(app) == ["◀"], "\(rows(app))")
    }

    @Test("A two-column split has the sidebar's button alone")
    func twoColumns() {
        TwoColumnApp.visibility.value = .all
        let app = running(TwoColumnApp())
        #expect(barArrows(app) == ["◀"], "\(rows(app))")
    }
}
