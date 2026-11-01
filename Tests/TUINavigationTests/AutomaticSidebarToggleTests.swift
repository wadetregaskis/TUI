//  🖥️ TUI — A Terminal UI framework for Swift
//  AutomaticSidebarToggleTests.swift
//
//  The sidebar button a window's top bar shows by default, at its leading edge,
//  for the window's first split view — only in a bar the page already has, and
//  not where the toggle was removed or the page placed one itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUINavigation
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

/// How a page's top bar comes about.
private enum Arrangement {
    /// An item of the page's in the top bar.
    case barItem
    /// No toolbar at all.
    case noBar
    /// An item in the top bar, and the toggle removed.
    case removed
    /// An item in the top bar, and the page's own sidebar button in the bottom bar.
    case placedByPage
    /// An item in the top bar, which is hidden.
    case hiddenBar
}

private struct Page: View {
    let arrangement: Arrangement
    let visibility: Visibility

    private var split: some View {
        NavigationSplitView(columnVisibility: visibility.binding) {
            Text("SIDE")
        } detail: {
            Text("DETAIL")
        }
    }

    var body: some View {
        switch arrangement {
        case .barItem:
            split.toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        case .noBar:
            split
        case .removed:
            split.toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
                .toolbar(removing: .sidebarToggle)
        case .placedByPage:
            split.toolbar {
                ToolbarItem(placement: .primaryAction) { Text("ITEM") }
                DefaultToolbarItem(kind: .sidebarToggle, placement: .bottomBar)
            }
        case .hiddenBar:
            split.toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
                .toolbarVisibility(.hidden, for: .windowToolbar)
        }
    }
}

private struct BarItemApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .barItem, visibility: Self.visibility) } }
}

private struct HiddenSidebarApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .barItem, visibility: Self.visibility) } }
}

private struct NoBarApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .noBar, visibility: Self.visibility) } }
}

private struct RemovedApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .removed, visibility: Self.visibility) } }
}

private struct PlacedApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .placedByPage, visibility: Self.visibility) } }
}

private struct HiddenBarApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .hiddenBar, visibility: Self.visibility) } }
}

/// A split nested in another's detail column: the outer one is the window's.
private struct NestedApp: App {
    static let outer = Visibility(.all)
    static let inner = Visibility(.all)
    init() {}
    var body: some Scene {
        WindowGroup {
            NavigationSplitView(columnVisibility: Self.outer.binding) {
                Text("OUTER")
            } detail: {
                NavigationSplitView(columnVisibility: Self.inner.binding) {
                    Text("INNER")
                } detail: {
                    Text("DETAIL")
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

@MainActor
@Suite("The top bar's automatic sidebar button", .rendersEnglishUI)
struct AutomaticSidebarToggleTests {
    /// `app` after five frames: a bar is adopted a frame or two after its items
    /// are first declared, and the split leaves out its edge column the frame
    /// after the bar first draws the button.
    private func running<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 50, height: 12)
        for index in 1...5 { headless.frame(atNanos: Int64(index) * 16_666_667) }
        return headless
    }

    private func rows(_ app: TestApp) -> [String] {
        app.screen.lines
    }

    /// The top bar's item row: the one holding "ITEM".
    private func barRow(_ app: TestApp) -> String? {
        rows(app).first { $0.contains("ITEM") }
    }

    private func click(_ app: TestApp, on text: String, in row: Int) {
        let line = rows(app)[row]
        guard let range = line.range(of: text) else { return }
        let column = line.distance(from: line.startIndex, to: range.lowerBound)
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
    }

    @Test("A top bar the page has shows the button at its leading edge, before the page's items")
    func leadingButton() throws {
        BarItemApp.visibility.value = .all
        let app = running(BarItemApp())
        let bar = try #require(barRow(app), "\(rows(app))")
        let arrow = try #require(bar.range(of: "◀"), "\(rows(app))")
        let item = try #require(bar.range(of: "ITEM"))
        #expect(arrow.lowerBound < item.lowerBound, "\(bar)")
        #expect(bar.distance(from: bar.startIndex, to: arrow.lowerBound) <= 4, "at the leading edge: \(bar)")
    }

    @Test("A click on it hides the sidebar; the split's edge column stays out")
    func clickHides() throws {
        HiddenSidebarApp.visibility.value = .all
        let app = running(HiddenSidebarApp())
        let barIndex = try #require(rows(app).firstIndex { $0.contains("ITEM") }, "\(rows(app))")
        click(app, on: "◀", in: barIndex)
        for index in 6...8 { app.frame(atNanos: Int64(index) * 16_666_667) }
        #expect(HiddenSidebarApp.visibility.value == .detailOnly)
        let screen = rows(app)
        #expect(barRow(app)?.contains("▶") == true, "\(screen)")
        #expect(screen.first { $0.contains("DETAIL") }?.hasPrefix("DETAIL") == true, "no edge column: \(screen)")
    }

    @Test("With no top bar there is no button, and the split keeps its edge column")
    func noBarNoButton() {
        NoBarApp.visibility.value = .detailOnly
        let app = running(NoBarApp())
        let screen = rows(app)
        #expect(screen.first { $0.contains("DETAIL") }?.hasPrefix(" DETAIL") == true, "\(screen)")
        #expect(screen.filter { $0.contains("▶") }.count == 1, "the edge's alone: \(screen)")
    }

    @Test("toolbar(removing: .sidebarToggle) removes it")
    func removedNoButton() throws {
        RemovedApp.visibility.value = .all
        let app = running(RemovedApp())
        let bar = try #require(barRow(app), "\(rows(app))")
        #expect(!bar.contains("◀") && !bar.contains("▶"), "\(bar)")
    }

    @Test("A sidebar button the page placed itself is the only one")
    func placedByPage() throws {
        PlacedApp.visibility.value = .all
        let app = running(PlacedApp())
        let screen = rows(app)
        let bar = try #require(barRow(app), "\(screen)")
        #expect(!bar.contains("◀"), "not in the top bar: \(bar)")
        let itemRow = try #require(screen.firstIndex { $0.contains("ITEM") })
        let sideRow = try #require(screen.firstIndex { $0.contains("SIDE") })
        #expect(screen.indices.contains { $0 > sideRow && $0 != itemRow && screen[$0].contains("▐ ◀ ▌") },
            "in the bottom bar: \(screen)")
    }

    @Test("A hidden top bar shows none, and the split keeps its edge column")
    func hiddenBar() {
        HiddenBarApp.visibility.value = .detailOnly
        let app = running(HiddenBarApp())
        let screen = rows(app)
        #expect(!screen.contains { $0.contains("ITEM") }, "\(screen)")
        #expect(screen.first { $0.contains("DETAIL") }?.hasPrefix(" DETAIL") == true, "\(screen)")
    }

    @Test("Of nested split views, the outer one's sidebar is the window's")
    func nestedOuter() throws {
        NestedApp.outer.value = .all
        NestedApp.inner.value = .all
        let app = running(NestedApp())
        let barIndex = try #require(rows(app).firstIndex { $0.contains("ITEM") }, "\(rows(app))")
        click(app, on: "◀", in: barIndex)
        for index in 6...7 { app.frame(atNanos: Int64(index) * 16_666_667) }
        #expect(NestedApp.outer.value == .detailOnly)
        #expect(NestedApp.inner.value == .all)
    }
}
