//  🖥️ TUI — A Terminal UI framework for Swift
//  TransliteratedTableTests.swift
//
//  Under `TUI_PLAIN_TEXT=transliterate` a table's string cells and headers are
//  spelled in ASCII as a `Text` would be, though the table draws them as
//  strings, and its columns are measured at the spelled width.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITables
@testable import TUITestSupport

@MainActor
@Suite("Tables under transliteration")
struct TransliteratedTableTests {
    private struct City: Identifiable {
        let id: Int
        let name: String
    }

    private static let rows = [City(id: 1, name: "Москва"), City(id: 2, name: "北京")]

    private func drawn(_ view: some View) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.transliteratesText = true
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
    }

    #if canImport(Darwin)
        @Test("String cells and the header are spelled, and fit whole")
        func stringCells() {
            let lines = drawn(Table(Self.rows) { TableColumn("Город", value: \City.name) })
            #expect(lines.contains("Gorod"), "\(lines)")
            #expect(lines.contains("Moskva") && lines.contains("bei jing"), "\(lines)")
        }

        @Test("Text cells are spelled on the table's own plain path", arguments: [1, 3])
        func textCells(lineLimit: Int) {
            let lines = drawn(
                Table(Self.rows) {
                    TableColumn("City") { (city: City) in Text(verbatim: city.name) }.lineLimit(lineLimit)
                })
            #expect(lines.contains("Moskva") && lines.contains("bei jing"), "\(lines)")
        }
    #endif
}
