//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorMemoryTests.swift
//
//  What an editor holds for a large text, per line: the heap a
//  `TestHighlightSession`, a `TextEditor` after its first frame, and one
//  highlighted, keep for a JSON-like document. Opt-in
//  (`TUI_EDITOR_MEMORY=1,10`, the sizes in MB): it reports, and asserts
//  only a loose ceiling, so a run measures in a release build what it has to.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
import Darwin
import Foundation
import Testing

@testable import TUIFoundation
import TUIJSONStyler
@_spi(TextEditorHighlighting) import TUITesting
@testable import TUITestSupport
@_spi(TextEditorHighlighting) @testable import TUITextInput

@MainActor
@Suite(
    "Text editor: the heap a large text costs, per line",
    .enabled(if: ProcessInfo.processInfo.environment["TUI_EDITOR_MEMORY"] != nil))
struct TextEditorMemoryTests {
    /// The sizes asked for, in MB.
    nonisolated static var sizes: [Int] {
        (ProcessInfo.processInfo.environment["TUI_EDITOR_MEMORY"] ?? "1")
            .split(separator: ",").compactMap { Int($0) }
    }

    /// A JSON array of records about 30 bytes a line, `megabytes` long.
    static func document(megabytes: Int) -> (text: String, lines: Int) {
        var text = "[\n"
        text.reserveCapacity(megabytes << 20 + 64)
        var lines = 1
        while text.utf8.count < megabytes << 20 {
            text += "  {\"id\": \(lines), \"v\": \"abc\"},\n"
            lines += 1
        }
        text += "]"
        return (text, lines + 1)
    }

    /// The bytes malloc's zones hold now.
    static func heapInUse() -> Int {
        var stats = malloc_statistics_t()
        unsafe malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// What `make` leaves held, per line of `lines`, printed under `label`.
    static func measure<Held>(_ label: String, lines: Int, _ make: () async throws -> Held) async rethrows -> Double {
        let before = heapInUse()
        let held = try await make()
        let after = heapInUse()
        withExtendedLifetime(held) {}
        let perLine = Double(after - before) / Double(lines)
        print("EDITOR-MEMORY \(label): \((after - before) >> 10) KiB, \(perLine.formatted(.number.precision(.fractionLength(1)))) B/line over \(lines) lines")
        return perLine
    }

    @Test("A highlight session, an editor and a highlighted editor, per line", arguments: sizes)
    func perLine(megabytes: Int) async throws {
        let (text, lines) = Self.document(megabytes: megabytes)
        print("EDITOR-MEMORY \(megabytes) MB: \(text.utf8.count) bytes, \(lines) lines")

        _ = await Self.measure("lines alone ([[Character]])", lines: lines) {
            text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).map { Array($0) }
        }
        _ = await Self.measure("EditorLayout(text:)", lines: lines) { EditorLayout(text: text) }
        let layout = EditorLayout(text: text)
        _ = await Self.measure("WrappedRows at 79 cells", lines: lines) {
            WrappedRows(lines: layout.lines, width: 79, tabWidth: .periodic(4))
        }
        do {
            let context = makeRenderContext(width: 80, height: 24)
            _ = renderToBuffer(TextEditor(text: .constant(text)), context: context)
            let handler = context.environment.focusManager?.activeSection?.focusables
                .compactMap { $0 as? TextEditorHandler }.first
            let kept = handler?.cachedLayout?.wrappings.map { "\($0.rows.width)" } ?? []
            print("EDITOR-MEMORY handler: wrappings at widths \(kept), display layout \(handler?.cachedDisplayLayout != nil)")
        }
        _ = await Self.measure("TestHighlightSession", lines: lines) {
            TestHighlightSession<JSONToken>(text: text, visibleLines: 0..<24)
        }

        let editor = await Self.measure("TextEditor, first frame", lines: lines) { () -> TestApp in
            let app = TestApp(width: 80, height: 24) { TextEditor(text: .constant(text)) }
            #expect(app.screen.contains("\"id\": 1,"))
            return app
        }
        let highlighted = try await Self.measure("TextEditor highlighted, first publish", lines: lines) { () -> TestApp in
            let app = TestApp(width: 80, height: 24) {
                TextEditor(text: .constant(text)).textEditorHighlighter(JSONHighlighter(), style: JSONLineStyler.style)
            }
            try await app.wait(until: { app.screen.style(of: "\"id\"")?.foreground != nil })
            return app
        }
        // A loose ceiling: a line's bytes are tens, not thousands.
        #expect(editor < 4_000 && highlighted < 4_000)
    }
}
#endif
