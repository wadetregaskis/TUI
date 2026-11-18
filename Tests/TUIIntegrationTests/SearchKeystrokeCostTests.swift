//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchKeystrokeCostTests.swift
//
//  A keystroke in a `.searchable` field builds the rows the filtered list or
//  table shows, not the rows it filtered: the app's filter runs over its data,
//  and the framework draws only the window. On a page and in a sheet alike.
//
//  PERFCASE-F11 read a sheet's 500 rows built on a keystroke as the search's.
//  It was type select: the field leaves the first focus to the content, so a
//  key typed before Find (⌃F) or a Tab reaches the field is the list's, and a
//  prefix no row starts with asks every row for its text (`TypeSelectScanTests`).
//  The last test pins that routing, which is what the perf case now steps past.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
@testable import TUIApp
@testable import TUIFoundation
import TUITesting

@MainActor
private final class SearchedRows {
    var query = ""
    var cells = 0
    let entries = (0..<2_000).map(SearchedEntry.init)

    var shown: [SearchedEntry] { query.isEmpty ? entries : entries.filter { $0.name.contains(query) } }
    var binding: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
}

private struct SearchedEntry: Identifiable, Hashable {
    let id: Int
    var name: String { "entry \(id)" }
}

/// A row an app builds from views, which type select can only draw to read.
private struct SearchedRow: View {
    let entry: SearchedEntry

    var body: some View {
        HStack {
            Text(verbatim: entry.name)
            Spacer()
            Text(verbatim: "\(entry.id % 7)")
        }
    }
}

@MainActor
@Suite("A keystroke in a search field builds what the filtered content shows")
struct SearchKeystrokeCostTests {
    /// The screen's rows: no more than this many content rows can show.
    private static let height = 20

    /// A searchable list of `model`'s rows, on the page or in a sheet over a
    /// line of text.
    private static func list(_ model: SearchedRows, inSheet: Bool) -> TestApp {
        TestApp(width: 60, height: height) {
            let list = List { ForEach(model.shown) { SearchedRow(entry: $0) } }.searchable(text: model.binding)
            if inSheet {
                AnyView(Text(verbatim: "behind").sheet(isPresented: .constant(true)) { list })
            } else {
                AnyView(list)
            }
        }
    }

    /// The rows `app` builds for the keys `text` types after Find put the
    /// keyboard in the field.
    private static func rowsBuilt(typing text: String, in app: TestApp) -> Int {
        _ = app.screen
        app.press(.character("f"), modifiers: .control)
        let before = app.headless.renderCache.rowWork.rendered
        app.type(text)
        return app.headless.renderCache.rowWork.rendered - before
    }

    @Test("A searchable list builds about a screenful of rows a keystroke, on a page and in a sheet", arguments: [false, true])
    func list(inSheet: Bool) {
        let model = SearchedRows()
        let app = Self.list(model, inSheet: inSheet)
        let built = Self.rowsBuilt(typing: "17", in: app)
        #expect(model.query == "17", "the keys reached the field")
        // Two keystrokes, each drawing at most the screen's rows; the list
        // filtered to "1" still has hundreds of rows, to "17" over a hundred.
        #expect(built > 0, "nothing was drawn, so this proved nothing")
        #expect(built <= 2 * Self.height, "\(built) rows built for two keystrokes")
    }

    @Test("A searchable table reads the cells of about a screenful of rows a keystroke, in a sheet")
    func table() {
        let model = SearchedRows()
        let app = TestApp(width: 60, height: Self.height) {
            Text(verbatim: "behind").sheet(isPresented: .constant(true)) {
                Table(model.shown) {
                    TableColumn("Name") { (entry: SearchedEntry) in
                        model.cells += 1
                        return Text(verbatim: entry.name)
                    }
                }
                .searchable(text: model.binding)
            }
        }
        _ = app.screen
        app.press(.character("f"), modifiers: .control)
        model.cells = 0
        app.type("17")
        #expect(model.query == "17", "the keys reached the field")
        #expect(model.cells > 0, "nothing was drawn, so this proved nothing")
        #expect(model.cells <= 2 * Self.height, "\(model.cells) cells read for two keystrokes")
    }

    @Test("In a sheet the list holds the first focus: a key typed before Find is its type select, not a query")
    func firstFocusIsTheList() {
        let model = SearchedRows()
        let app = Self.list(model, inSheet: true)
        _ = app.screen
        app.type("zz")
        #expect(model.query.isEmpty, "the keys went to the field: \(model.query)")
        app.press(.character("f"), modifiers: .control)
        app.type("zz")
        #expect(model.query == "zz")
    }
}
