//  🖥️ TUI — A Terminal UI framework for Swift
//  TestScreen.swift
//
//  What a TestApp's screen shows, as text a test can read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

/// What a ``TestApp`` has on its screen at one moment.
///
/// It is a value: keep one, act on the app, and compare the two. Printing one,
/// as a failing `#expect` does, shows the screen row by row.
public struct TestScreen: Equatable, Sendable, CustomStringConvertible {
    /// The rows, top to bottom, with what terminal styling they have.
    ///
    /// Each holds the escape codes a terminal would be sent for its colours and
    /// attributes. For checking that something is styled at all; a test of
    /// layout or wording is better off with ``lines``.
    public let styledLines: [String]

    /// The rows, top to bottom, as plain text with no trailing spaces.
    ///
    /// There is one for each row of the terminal, so an empty row is an empty
    /// string.
    public let lines: [String]

    init(styledLines: [String]) {
        self.styledLines = styledLines
        lines = styledLines.map { line in
            var plain = line.stripped
            while plain.last == " " { plain.removeLast() }
            return plain
        }
    }

    /// The whole screen as one string, its rows joined by newlines, without the
    /// empty rows at the bottom.
    public var text: String {
        var lines = lines
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Whether `text` shows anywhere on the screen, all on one row.
    public func contains(_ text: String) -> Bool {
        lines.contains { $0.contains(text) }
    }

    /// The first row showing `text`, or `nil` if none does.
    public func line(containing text: String) -> String? {
        lines.first { $0.contains(text) }
    }

    /// Where `text` first shows, reading from the top: the cell of its first
    /// character. `nil` if it does not show.
    public func location(of text: String) -> CellPoint? {
        for (row, line) in lines.enumerated() {
            if let range = line.range(of: text) { return Self.point(of: range, in: line, row: row) }
        }
        return nil
    }

    /// Everywhere `text` shows, reading from the top and from the left: the
    /// cell of the first character of each. Matches do not overlap.
    public func locations(of text: String) -> [CellPoint] {
        guard !text.isEmpty else { return [] }
        var found: [CellPoint] = []
        for (row, line) in lines.enumerated() {
            var rest = line.startIndex..<line.endIndex
            while let range = line.range(of: text, range: rest) {
                found.append(Self.point(of: range, in: line, row: row))
                rest = range.upperBound..<line.endIndex
            }
        }
        return found
    }

    /// The cell a range of `line` starts at. A cell, not a character: a wide
    /// character before it takes two.
    private static func point(of range: Range<String.Index>, in line: String, row: Int) -> CellPoint {
        CellPoint(x: String(line[..<range.lowerBound]).strippedLength, y: row)
    }

    /// The screen as it looks, row by row.
    public var description: String {
        lines.joined(separator: "\n")
    }

    /// Two screens are equal when they show the same thing, styling and all.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.styledLines == rhs.styledLines
    }
}
