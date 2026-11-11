//  🖥️ TUI — A Terminal UI framework for Swift
//  BrowserEntryIconTests.swift
//
//  The Tables page's icon column, two cells wide: under
//  `TUI_PLAIN_TEXT=transliterate` an emoji is spelled by its name, and the
//  column cut `:file_folder:` to `:.`. It draws the type letter a file panel
//  draws there instead.
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Foundation
import Testing

@testable import Example
import TUI
@testable import TUIFoundation

@MainActor
@Suite("The file browser's icon column")
struct BrowserEntryIconTests {
    private static let entries = [
        BrowserEntry(id: "/a/..", name: "..", kind: .parent, url: URL(fileURLWithPath: "/"), size: "", modified: ""),
        BrowserEntry(id: "/a/b", name: "b", kind: .directory, url: URL(fileURLWithPath: "/a/b"), size: "", modified: ""),
        BrowserEntry(id: "/a/c", name: "c", kind: .file, url: URL(fileURLWithPath: "/a/c"), size: "", modified: ""),
    ]

    /// The page's two leading columns, drawn with words spelled `spelling`.
    private func drawn(_ spelling: TextSpelling) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.textSpelling = spelling
        let context = RenderContext(availableWidth: 20, availableHeight: 6, environment: environment, tuiContext: TUIContext())
        let table = Table(Self.entries) {
            TableColumn("") { (entry: BrowserEntry) in BrowserEntryIcon(entry: entry) }
                .width(2)
            TableColumn("Name", value: \BrowserEntry.name)
        }
        return renderToBuffer(table, context: context).lines.map(\.stripped)
    }

    /// What the icon column draws on `name`'s row, inside the table's border.
    private func icon(of name: String, in lines: [String]) -> String {
        let rows = lines.map { $0.split { $0 == " " || $0 == "│" } }
        guard let row = rows.first(where: { $0.count == 2 && $0[1] == Substring(name) }) else { return "" }
        return String(row[0])
    }

    @Test("In ASCII a folder is d and a file f, and as written their emoji")
    func letters() {
        let ascii = drawn(.ascii(.standard))
        #expect(icon(of: "b", in: ascii) == "d", "\(ascii)")
        #expect(icon(of: "c", in: ascii) == "f", "\(ascii)")
        #expect(icon(of: "..", in: ascii) == "^", "\(ascii)")
        let written = drawn(.asWritten)
        #expect(icon(of: "b", in: written) == "📁", "\(written)")
        #expect(icon(of: "c", in: written) == "📄", "\(written)")
        #expect(icon(of: "..", in: written) == "↰", "\(written)")
    }
}

#endif
