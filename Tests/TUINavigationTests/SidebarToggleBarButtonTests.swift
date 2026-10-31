//  🖥️ TUI — A Terminal UI framework for Swift
//  SidebarToggleBarButtonTests.swift
//
//  `DefaultToolbarItem(kind: .sidebarToggle)`: a button in a bar that hides and
//  shows a split view's sidebar — the split it is declared in, else the
//  window's — standing in for the ▶ edge column while it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIFoundation
import TUINavigation
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

/// Where a page declares its sidebar button.
private enum Arrangement {
    /// In the detail column.
    case inDetail
    /// Round the split view.
    case aroundSplit
    /// In the detail column of a split whose toggle was removed.
    case inRemovedSplit
    /// No button at all.
    case none
}

private struct SplitPage: View {
    let arrangement: Arrangement
    let visibility: Visibility

    var body: some View {
        switch arrangement {
        case .inDetail:
            NavigationSplitView(columnVisibility: visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL").toolbar { DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) }
            }
        case .aroundSplit:
            NavigationSplitView(columnVisibility: visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL")
            }
            .toolbar { DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) }
        case .inRemovedSplit:
            NavigationSplitView(columnVisibility: visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL").toolbar {
                    DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)
                    ToolbarItem(placement: .primaryAction) { Text("ITEM") }
                }
            }
            .toolbar(removing: .sidebarToggle)
        case .none:
            NavigationSplitView(columnVisibility: visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL")
            }
        }
    }
}

private struct InDetailApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { SplitPage(arrangement: .inDetail, visibility: Self.visibility) } }
}

private struct AroundSplitApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { SplitPage(arrangement: .aroundSplit, visibility: Self.visibility) } }
}

private struct RemovedApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene { WindowGroup { SplitPage(arrangement: .inRemovedSplit, visibility: Self.visibility) } }
}

private struct ShownApp: App {
    static let visibility = Visibility(.all)
    init() {}
    var body: some Scene { WindowGroup { SplitPage(arrangement: .inDetail, visibility: Self.visibility) } }
}

/// The button in the top bar and the key hints in the bottom one.
private struct HintApp: App {
    static let visibility = Visibility(.detailOnly)
    init() {}
    var body: some Scene {
        WindowGroup {
            NavigationSplitView(columnVisibility: Self.visibility.binding) {
                Text("SIDE")
            } detail: {
                Text("DETAIL").toolbar {
                    DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
            }
        }
    }
}

/// A split nested in another's detail column, the button in the inner one's.
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
                    Text("DETAIL").toolbar { DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) }
                }
            }
        }
    }
}

@MainActor
@Suite("A toolbar's sidebar button", .rendersEnglishUI)
struct SidebarToggleBarButtonTests {
    /// `app` after five frames: a bar is adopted a frame or two after its items
    /// are first declared, and the split leaves out its edge column the frame
    /// after the bar first draws the button.
    private func running<A: App>(_ app: A) -> HeadlessApp {
        let headless = HeadlessApp(app, width: 50, height: 12)
        for index in 1...5 { headless.frame(atNanos: Int64(index) * 16_666_667) }
        return headless
    }

    /// Two more frames of `app`, after an input.
    private func settle(_ app: HeadlessApp, from frame: Int = 6) {
        for index in frame...(frame + 1) { app.frame(atNanos: Int64(index) * 16_666_667) }
    }

    private func rows(_ app: HeadlessApp) -> [String] {
        app.screen.map(\.stripped)
    }

    /// The row and column of the first `text` on screen.
    private func position(of text: String, in app: HeadlessApp) -> (row: Int, column: Int)? {
        let screen = rows(app)
        guard let row = screen.firstIndex(where: { $0.contains(text) }),
            let range = screen[row].range(of: text)
        else { return nil }
        return (row, screen[row].distance(from: screen[row].startIndex, to: range.lowerBound))
    }

    private func click(_ app: HeadlessApp, at point: (row: Int, column: Int)) {
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: point.column, y: point.row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: point.column, y: point.row))
    }

    @Test("Declared in the detail column, a hidden sidebar's button shows ▶ in the bar, and the edge column goes")
    func buttonStandsInForTheEdge() throws {
        InDetailApp.visibility.value = .detailOnly
        let app = running(InDetailApp())
        let screen = rows(app)
        let button = try #require(position(of: "▶", in: app), "\(screen)")
        let detail = try #require(position(of: "DETAIL", in: app), "\(screen)")
        #expect(button.row < detail.row, "the ▶ is the bar's, above the page: \(screen)")
        #expect(detail.column == 0, "no edge column before the detail: \(screen)")
        #expect(!screen[detail.row...].contains { $0.contains("▶") }, "\(screen)")
    }

    @Test("A click on the button shows the sidebar, and the button turns to ◀")
    func clickShowsTheSidebar() throws {
        InDetailApp.visibility.value = .detailOnly
        let app = running(InDetailApp())
        click(app, at: try #require(position(of: "▶", in: app), "\(rows(app))"))
        settle(app)
        #expect(InDetailApp.visibility.value == .all)
        let screen = rows(app)
        #expect(position(of: "SIDE", in: app) != nil, "\(screen)")
        let button = try #require(position(of: "◀", in: app), "\(screen)")
        #expect(button.row < (position(of: "SIDE", in: app)?.row ?? 0), "\(screen)")
        click(app, at: button)
        settle(app, from: 8)
        #expect(InDetailApp.visibility.value == .detailOnly, "and back: \(rows(app))")
    }

    @Test("While the sidebar shows, the divider keeps its ◀ beside the bar's")
    func dividerKeepsItsArrow() throws {
        ShownApp.visibility.value = .all
        let app = running(ShownApp())
        let screen = rows(app)
        let side = try #require(position(of: "SIDE", in: app), "\(screen)")
        let arrows = screen.indices.filter { screen[$0].contains("◀") }
        #expect(arrows.contains { $0 < side.row }, "the bar's: \(screen)")
        #expect(arrows.contains { $0 >= side.row }, "the divider's: \(screen)")
    }

    @Test("Declared round the split view, it toggles the window's split")
    func aroundTheSplit() throws {
        AroundSplitApp.visibility.value = .detailOnly
        let app = running(AroundSplitApp())
        let screen = rows(app)
        let button = try #require(position(of: "▶", in: app), "\(screen)")
        #expect(position(of: "DETAIL", in: app)?.column == 0, "\(screen)")
        click(app, at: button)
        settle(app)
        #expect(AroundSplitApp.visibility.value == .all)
    }

    @Test("In a split whose toggle was removed it draws nothing, and toggles nothing")
    func removedSplitDrawsNothing() throws {
        RemovedApp.visibility.value = .detailOnly
        let app = running(RemovedApp())
        let screen = rows(app)
        #expect(position(of: "ITEM", in: app) != nil, "the bar is there: \(screen)")
        #expect(!screen.contains { $0.contains("▶") || $0.contains("◀") }, "\(screen)")
    }

    @Test("In a nested split's column it toggles that split, not the outer one")
    func nestedTogglesTheInner() throws {
        NestedApp.outer.value = .all
        NestedApp.inner.value = .all
        let app = running(NestedApp())
        let screen = rows(app)
        let inner = try #require(position(of: "INNER", in: app), "\(screen)")
        // The bar's last ◀: the window's own button for the outer split comes
        // first, at the leading edge.
        let button = try #require(
            screen.indices.first { $0 < inner.row && screen[$0].contains("◀") }.map { row in
                (row, screen[row].distance(
                    from: screen[row].startIndex, to: screen[row].range(of: "◀", options: .backwards)!.lowerBound))
            }, "\(screen)")
        click(app, at: button)
        settle(app)
        #expect(NestedApp.inner.value == .detailOnly)
        #expect(NestedApp.outer.value == .all)
    }

    @Test("Return on the focused button names what it does in the status bar's hints")
    func statusBarHint() throws {
        HintApp.visibility.value = .detailOnly
        let app = running(HintApp())
        // The bar's section comes after the page's in the Tab ring.
        for index in 0..<4 where !rows(app).contains(where: { $0.contains("show sidebar") }) {
            _ = app.send(KeyEvent(key: .tab))
            app.frame(atNanos: Int64(6 + index) * 16_666_667)
        }
        #expect(rows(app).contains { $0.contains("show sidebar") }, "\(rows(app))")
    }
}
