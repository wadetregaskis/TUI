//  🖥️ TUI — A Terminal UI framework for Swift
//  DefaultToolbarItemTests.swift
//
//  `DefaultToolbarItem(kind:placement:)` and `toolbar(removing: .search)`
//  (refusal review O17): the searchable's field drawn in the bar the item
//  places it in instead of above the page, Tab and typing reaching it there; the field
//  drawn nowhere once removed; the title moved from the top bar's slot.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

/// The query a page searches, by reference so the binding a frame built reaches
/// it. Each app has its own, so suites running side by side share nothing.
private final class Query: @unchecked Sendable {
    var text = ""
    var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

/// How a page places its searchable's field.
private enum Arrangement {
    /// No toolbar: the field above the page.
    case plain
    /// The search item in a toolbar inside the searchable's content.
    case itemInside
    /// The search item in a toolbar round the searchable.
    case itemAround
    /// `toolbar(removing: .search)` inside the searchable's content.
    case removedInside
    /// `toolbar(removing: .search)` round the searchable.
    case removedAround
}

private struct SearchPage: View {
    let arrangement: Arrangement
    let query: Query

    var body: some View {
        switch arrangement {
        case .plain:
            Text("BODY").searchable(text: query.binding)
        case .itemInside:
            Text("BODY")
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                .searchable(text: query.binding)
        case .itemAround:
            Text("BODY")
                .searchable(text: query.binding)
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
        case .removedInside:
            Text("BODY").toolbar(removing: .search).searchable(text: query.binding)
        case .removedAround:
            Text("BODY").searchable(text: query.binding).toolbar(removing: .search)
        }
    }
}

private struct PlainApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .plain, query: Self.query) } }
}

private struct ItemInsideApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .itemInside, query: Self.query) } }
}

/// The search item inside the searchable, for the typing test alone: its query
/// is typed into, which the placement tests' prompt must not see.
private struct TypingApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .itemInside, query: Self.query) } }
}

private struct ItemAroundApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .itemAround, query: Self.query) } }
}

private struct RemovedInsideApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .removedInside, query: Self.query) } }
}

private struct RemovedAroundApp: App {
    static let query = Query()
    init() {}
    var body: some Scene { WindowGroup { SearchPage(arrangement: .removedAround, query: Self.query) } }
}

/// A titled page whose title a default item moves to the bottom bar.
private struct TitleItemApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("BODY")
                .navigationTitle("PAGE-TITLE")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("ITEM") }
                    DefaultToolbarItem(kind: .title, placement: .bottomBar)
                }
        }
    }
}

@MainActor
@Suite("Default toolbar items", .rendersEnglishUI)
struct DefaultToolbarItemTests {
    /// `app` after three frames.
    private func running<A: App>(_ app: A) -> HeadlessApp {
        let headless = HeadlessApp(app, width: 40, height: 12)
        var now: Int64 = 0
        for _ in 0..<3 {
            now += 16_666_667
            headless.frame(atNanos: now)
        }
        return headless
    }

    /// What `app` shows after three frames.
    private func drawn(_ app: some App) -> [String] {
        running(app).screen.map(\.stripped)
    }

    /// The rows holding the search field's prompt, against the page's row.
    private func fieldRows(_ rows: [String]) -> (field: [Int], page: Int?) {
        (rows.indices.filter { rows[$0].contains("Search") }, rows.firstIndex { $0.contains("BODY") })
    }

    @Test("With no item, the field is above the page")
    func plain() {
        let rows = drawn(PlainApp())
        let (field, page) = fieldRows(rows)
        #expect(field.count == 1 && page != nil && field[0] < page!, "\(rows)")
    }

    @Test(
        "A search item puts the field in its bar, declared inside the searchable or round it",
        arguments: [false, true])
    func itemMovesTheField(around: Bool) {
        let rows = around ? drawn(ItemAroundApp()) : drawn(ItemInsideApp())
        let (field, page) = fieldRows(rows)
        #expect(field.count == 1, "one field, not two: \(rows)")
        #expect(page != nil && field.allSatisfy { $0 > page! }, "below the page, in the bottom bar: \(rows)")
    }

    @Test("Tab reaches the field in the bar, and typing goes into it")
    func typingReachesTheField() {
        let query = TypingApp.query
        query.text = ""
        let app = running(TypingApp())
        _ = app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 100_000_000)
        for character in "mars" { _ = app.send(KeyEvent(character: character)) }
        app.frame(atNanos: 200_000_000)
        #expect(query.text == "mars", "\(app.screen.map(\.stripped))")
        #expect(app.screen.contains { $0.stripped.contains("mars") })
    }

    @Test("toolbar(removing: .search) draws the field nowhere, inside the searchable or round it", arguments: [false, true])
    func removal(around: Bool) {
        let rows = around ? drawn(RemovedAroundApp()) : drawn(RemovedInsideApp())
        let (field, page) = fieldRows(rows)
        #expect(field.isEmpty && page != nil, "\(rows)")
    }

    @Test("A title item moves the title from the top bar's slot to its bar")
    func titleItem() {
        let rows = drawn(TitleItemApp())
        let title = rows.indices.filter { rows[$0].contains("PAGE-TITLE") }
        let page = rows.firstIndex { $0.contains("BODY") }
        #expect(title.count == 1 && page != nil && title[0] > page!, "in the bottom bar, once: \(rows)")
        #expect(rows.contains { $0.contains("ITEM") }, "the top bar keeps its item")
    }
}
