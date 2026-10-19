//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableCellLocaleTests.swift
//
//  A `Text` made from a key in a table's cell reads it in the language the
//  table's `\.locale` names, as a `Text` anywhere else does (decisions
//  B-PARITYMISC-5). The plain cells are the ones at risk: the table draws them
//  as the string they hold, without measuring or drawing the `Text`, which is
//  where a `Text` reads its key again.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
import TUIkitTables
@testable import TUIkitTestSupport

@MainActor
@Suite("A key in a table's cell follows the table's locale", .rendersEnglishUI)
struct TableCellLocaleTests {
    private struct Chore: Identifiable {
        let id: Int
        let status: LocalizedStringKey
        let isBold: Bool
        var children: [Self]?
    }

    init() {
        // Keys of this suite's own, so no other suite reads them.
        LocalizationService.shared.registerWithoutRendering(translations: [
            "en": ["test.tableLocale.done": "Finished", "test.tableLocale.open": "Pending"],
            "de": ["test.tableLocale.done": "Erledigt", "test.tableLocale.open": "Offen"],
        ])
    }

    private static let rows = [
        Chore(id: 1, status: "test.tableLocale.done", isBold: false),
        Chore(id: 2, status: "test.tableLocale.open", isBold: true),
    ]

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func drawn(_ view: some View) -> String {
        renderToBuffer(view, context: context()).lines.map(\.stripped).joined(separator: "\n")
    }

    /// A column whose plain cells are drawn as strings and whose bold ones
    /// are rendered, so one column holds both.
    private func statusColumn(lineLimit: Int) -> some TableColumnContent<Chore, Never> {
        TableColumn("Status") { (chore: Chore) in
            chore.isBold ? Text(chore.status).bold() : Text(chore.status)
        }
        .lineLimit(lineLimit)
    }

    @Test("With no override the cells read the app's language")
    func noOverride() {
        let lines = drawn(Table(Self.rows) { statusColumn(lineLimit: 1) })
        #expect(lines.contains("Finished") && lines.contains("Pending"), "\(lines)")
    }

    @Test("A column's plain and styled cells both read the override's language", arguments: [1, 3])
    func overrideReachesEveryCell(lineLimit: Int) {
        let lines = drawn(
            Table(Self.rows) { statusColumn(lineLimit: lineLimit) }
                .environment(\.locale, Locale(identifier: "de_CH")))
        #expect(lines.contains("Erledigt"), "the plain cell, drawn as its string: \(lines)")
        #expect(lines.contains("Offen"), "the bold cell, rendered: \(lines)")
        #expect(!lines.contains("Finished") && !lines.contains("Pending"), "\(lines)")
    }

    @Test("An outline's first column, drawn after its triangle, reads the override's language")
    func outlineColumn() {
        let tree = [
            Chore(
                id: 1, status: "test.tableLocale.done", isBold: false,
                children: [Chore(id: 3, status: "test.tableLocale.done", isBold: false)]),
            Chore(id: 2, status: "test.tableLocale.open", isBold: true),
        ]
        let lines = drawn(
            Table(tree, children: \.children) { statusColumn(lineLimit: 1) }
                .environment(\.locale, Locale(identifier: "de")))
        #expect(lines.contains("\(TerminalSymbols.disclosureCollapsed) Erledigt"), "\(lines)")
        #expect(lines.contains("Offen"), "\(lines)")
        #expect(!lines.contains("Finished") && !lines.contains("Pending"), "\(lines)")
    }
}
