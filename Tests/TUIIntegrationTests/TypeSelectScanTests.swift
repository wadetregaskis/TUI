//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectScanTests.swift
//
//  What a type-select key press costs on a long list or table. A prefix is
//  matched against the rows from the cursor on and stops at the first match;
//  a prefix no row starts with, or a match far from the cursor, asks every row
//  it passes for its text. A list's plain `Text` row is read for it rather
//  than drawn as a measure (`LazyListRowContent.typeSelectText(ofPlainText:context:)`);
//  a view the app built is drawn, there being no other way to its words.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// Counts cell closures called, and holds a selection.
@MainActor private final class Builds {
    var count = 0
    var row: Int?

    var rowBinding: Binding<Int?> { Binding(get: { self.row }, set: { self.row = $0 }) }
}

private struct Entry: Identifiable, Hashable {
    let id: Int
    var name: String { "item \(id)" }
}

@MainActor
@Suite("Type select's scan")
struct TypeSelectScanTests {
    /// The cells a table of `rows` builds for a key whose match is the next
    /// row, and the row it then selects.
    private static func nearMatch(rows: Int) -> (built: Int, selected: Int?) {
        let builds = Builds()
        let entries = (0..<rows).map(Entry.init)
        let app = TestApp(width: 30, height: 12) {
            Table(entries, selection: builds.rowBinding) {
                TableColumn("Name") { (entry: Entry) in
                    builds.count += 1
                    return HStack(spacing: 0) { Text(verbatim: entry.name) }
                }
            }
        }
        _ = app.screen
        builds.count = 0
        app.press(.character("i"))
        let built = builds.count
        app.press(.space)
        return (built, builds.row)
    }

    @Test("A prefix stops at its first match from the cursor: a near match builds the same few cells at 1,000 and 10,000 rows")
    func stopsAtTheFirstMatch() {
        let small = Self.nearMatch(rows: 1_000)
        #expect(small.selected == 1)
        #expect(small.built < 50, "\(small.built)")
        #expect(Self.nearMatch(rows: 10_000).built == small.built)
    }

    /// A plain `Text` row's type-select text, read off it as a list's probe
    /// reads it, in `context`.
    private func read(_ row: any View, in context: RenderContext = makeRenderContext()) -> String? {
        LazyListRowContent.typeSelectText(ofPlainText: row, context: context)
    }

    @Test("A plain Text row is read for its text: its first line, without the spaces around it")
    func plainTextIsRead() {
        #expect(read(Text(verbatim: "item 5")) == "item 5")
        #expect(read(Text(verbatim: "  Alpha  \nBravo")) == "Alpha")
    }

    @Test("Anything else is drawn to be read: a styled Text, another view, a redacted row")
    func otherRowsAreDrawn() {
        #expect(read(Text(verbatim: "bold").bold()) == nil)
        #expect(read(HStack { Text(verbatim: "in a stack") }) == nil)
        var redacted = makeRenderContext()
        redacted.environment.redactionReasons = .placeholder
        #expect(read(Text(verbatim: "hidden"), in: redacted) == nil)
    }
}
