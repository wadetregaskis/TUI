//  🖥️ TUI — A Terminal UI framework for Swift
//  CursorReportRequestScanTests.swift
//
//  `KeyEvent.parse` reads `CSI 1 ; m R` as F3 with a modifier (Shift-F3 is
//  `CSI 1;2 R`), which is also the shape of a cursor-position report for row
//  1. That is safe only while TUI asks for no cursor report on row 1: its startup
//  exchanges fence on the status report, `CSI 5 n`, since 2026-10-05. Until
//  this scan, that rested on a comment; a `CSI 6 n` sent anywhere again would
//  have its row-1 answers typed as F3.
//
//  The one exception is the graphics handshake, which reads what a placement did
//  to the cursor and has no other way to. It moves off row 1 first, which
//  `TerminalGraphicsQueryTests` pins, and is fenced by `CSI 5 n` like the rest.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIFoundation
@testable import TUITestSupport

@Suite("Nothing but the graphics handshake asks the terminal for a cursor report")
struct CursorReportRequestScanTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Every line of code in every Swift file under `Sources/`, comments
    /// dropped: a comment that mentions `CSI 6 n` sends nothing.
    private static func codeLines() throws -> [(file: String, line: String)] {
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        var lines: [(file: String, line: String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                lines.append((url.lastPathComponent, String(line)))
            }
        }
        return lines
    }

    @Test("No code under Sources but the graphics handshake sends CSI 6 n, so CSI 1;m R can be read as F3")
    func noCursorReportRequest() throws {
        let lines = try Self.codeLines()
        #expect(
            lines.contains { $0.file == "Terminal+Exchange.swift" && $0.line.contains("[5n") },
            "the scan finds the status fence the exchanges use instead")
        // `[6n`, `[?6n` (DECXCPR), or a literal ending `6n`, which is how a
        // request built from a CSI prefix would end.
        let request = /\[\??6n|6n"/
        let requests = lines.filter { $0.file != "TerminalGraphicsQuery.swift" && $0.line.contains(request) }
            .map { "\($0.file): \($0.line)" }
        #expect(requests.isEmpty, "a cursor report's row-1 answer would arrive as a modified F3")
    }
}
