//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutSanity.swift
//
//  The checks every real-world screen in this folder is held to, written once:
//  nothing drawn outside the terminal or a control outside the screen, no two
//  controls overlapping, the focus on screen after every step, no blank filler
//  rows among a control's rows, nothing cut without a sign, and every row
//  reachable by the wheel, the paging keys and Tab. The owner, 2026-11-13:
//  "There's clearly still a *lot* of real world use-cases we're not covering
//  in tests", after unequal-length tables in a ScrollView drew blank rows.
//
//  The checks read only what a person sees, the screen's text, and where the
//  frame put each control, the regions it published for the pointer. A check
//  is never loosened to let a screen pass: a screen that fails one is a
//  finding, fixed or recorded as a known issue where it is tested.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting

/// A terminal size a real-world screen is driven at.
struct TerminalSize: Sendable, CustomTestStringConvertible {
    let width: Int
    let height: Int

    var testDescription: String { "\(width)×\(height)" }

    /// A tiny one, the two sizes people use most, and a big one.
    static let all: [Self] = [
        Self(width: 20, height: 6), Self(width: 40, height: 12), Self(width: 80, height: 24),
        Self(width: 120, height: 40),
    ]

    /// All but the tiny one, for a screen whose step needs more than six rows
    /// to mean anything (a sheet over a page, say); the tiny one is still run
    /// through ``LayoutSanity/check(_:_:sourceLocation:)`` where it is driven.
    static let usable: [Self] = Array(all.dropFirst())
}

extension CellRect {
    /// The smallest rectangle holding both.
    fileprivate func union(_ other: Self) -> Self {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        return Self(x: minX, y: minY, width: max(maxX, other.maxX) - minX, height: max(maxY, other.maxY) - minY)
    }

    /// Whether the two share a cell.
    fileprivate func overlaps(_ other: Self) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    /// Whether every cell of `other` is one of this one's.
    func contains(_ other: Self) -> Bool {
        x <= other.x && y <= other.y && maxX >= other.maxX && maxY >= other.maxY
    }

    /// Whether the cell at `point` is one of this one's.
    func contains(_ point: CellPoint) -> Bool {
        (x..<maxX).contains(point.x) && (y..<maxY).contains(point.y)
    }
}

extension TestApp {
    /// Where the last frame drew each control that can take the focus, by its
    /// focus ID: every visible region it published, joined. A control scrolled
    /// out of sight has none.
    var controlFrames: [String: CellRect] {
        _ = screen
        var frames: [String: CellRect] = [:]
        for region in services.mouseEventDispatcher.regions
        where region.width > 0 && region.height > 0 && !region.handlerID.isGeometryMarker {
            guard let focusID = region.focusID else { continue }
            let rect = CellRect(x: region.offsetX, y: region.offsetY, width: region.width, height: region.height)
            frames[focusID] = frames[focusID].map { $0.union(rect) } ?? rect
        }
        return frames
    }
}

/// One way a person moves through a screen.
enum NavigationStep: CustomStringConvertible {
    case wheelDown(over: String?)
    case pageDown
    case end
    case tab
    case down

    var description: String {
        switch self {
        case .wheelDown(let over): "wheel down over \(over ?? "the middle")"
        case .pageDown: "Page Down"
        case .end: "End"
        case .tab: "Tab"
        case .down: "Down"
        }
    }
}

@MainActor
enum LayoutSanity {
    /// The characters that draw chrome rather than content: box drawing,
    /// block elements (scroll bars, gauges' tracks), geometric shapes (scroll
    /// arrows, grips, disclosure triangles) and spaces. A row of only these is
    /// blank as far as content goes.
    static func isChrome(_ scalar: Unicode.Scalar) -> Bool {
        (0x2500...0x25FF).contains(scalar.value) || scalar == " " || scalar == "·"
    }

    /// Whether a row is filler: nothing on it but spaces, a scroll bar and
    /// the sides of the boxes it passes through. A box's top or bottom rule,
    /// or a divider, is drawing, not filler.
    static func isBlank(_ line: Substring) -> Bool {
        line.unicodeScalars.allSatisfy { scalar in
            scalar == " " || "│┃║▲▼".unicodeScalars.contains(scalar) || (0x2580...0x259F).contains(scalar.value)
        }
    }

    /// What every frame of every screen must be: the screen's rows each fit
    /// the terminal, every control lies on the screen, no two controls overlap
    /// unless one holds the other, and the focus, when a control has it, is on
    /// screen.
    ///
    /// The last is waived, by `focusMustShow`, only after the wheel: the wheel
    /// moves the view and never the focus, in SwiftUI as here, so it can
    /// scroll the focused control away. The next key brings it back.
    static func check(
        _ app: TestApp, _ step: String, focusMustShow: Bool = true, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (width, height) = app.size
        let screen = app.screen
        #expect(screen.lines.count == height, "\(step): \(screen.lines.count) rows", sourceLocation: sourceLocation)
        for (row, line) in screen.lines.enumerated() where line.strippedLength > width {
            Issue.record("\(step): row \(row) is \(line.strippedLength) cells wide:\n\(screen)", sourceLocation: sourceLocation)
        }
        let frames = app.controlFrames
        let bounds = CellRect(x: 0, y: 0, width: width, height: height)
        for (id, frame) in frames where !bounds.contains(frame) {
            Issue.record("\(step): \(id) at \(describe(frame)) is off the \(width)×\(height) screen", sourceLocation: sourceLocation)
        }
        let sorted = frames.sorted { $0.key < $1.key }
        for (index, (id, frame)) in sorted.enumerated() {
            for (otherID, other) in sorted[(index + 1)...]
            where frame.overlaps(other) && !frame.contains(other) && !other.contains(frame) {
                Issue.record(
                    "\(step): \(id) at \(describe(frame)) overlaps \(otherID) at \(describe(other)):\n\(screen)",
                    sourceLocation: sourceLocation)
            }
        }
        if focusMustShow, let focused = app.focusedID, frames[focused] == nil {
            Issue.record("\(step): the focus, \(focused), is not on screen:\n\(screen)", sourceLocation: sourceLocation)
        }
    }

    /// A rectangle as its corners, max edges exclusive.
    static func describe(_ rect: CellRect) -> String { "(\(rect.x),\(rect.y))–(\(rect.maxX),\(rect.maxY))" }

    /// Tabs until the control drawn where `text` shows has the focus.
    /// - Returns: Whether it took it within `limit` presses.
    @discardableResult
    static func focus(_ text: String, in app: TestApp, limit: Int = 8, sourceLocation: SourceLocation = #_sourceLocation)
        -> Bool
    {
        for _ in 0...limit {
            if let point = app.screen.location(of: text), let focused = app.focusedID,
                app.controlFrames[focused]?.contains(point) == true
            {
                return true
            }
            app.press(.tab)
        }
        Issue.record("\(limit) × Tab never focused \(text):\n\(app.screen)", sourceLocation: sourceLocation)
        return false
    }

    /// The row each label shows on, for those that show.
    static func rows(of labels: [String], in app: TestApp) -> [Int] {
        labels.compactMap { label in app.screen.lines.firstIndex { contains($0, word: label) } }
    }

    /// Whether `line` shows `label` as a whole word: `Row 1` does not match
    /// `Row 12`.
    static func contains(_ line: String, word label: String) -> Bool {
        var rest = line[...]
        while let range = rest.range(of: label) {
            let next = rest[range.upperBound...].first
            if next.map({ !$0.isLetter && !$0.isNumber }) ?? true { return true }
            rest = rest[range.upperBound...]
        }
        return false
    }

    /// The labels that show are on consecutive rows, in order: no blank filler
    /// row and nothing else between two of a control's rows. At least
    /// `atLeast` of them show.
    static func expectContiguous(
        _ app: TestApp, _ labels: [String], atLeast: Int = 1, _ step: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rows = rows(of: labels, in: app)
        #expect(
            rows.count >= atLeast, "\(step): \(rows.count) of \(labels.count) rows show:\n\(app.screen)",
            sourceLocation: sourceLocation)
        for (row, next) in zip(rows, rows.dropFirst()) where next != row + 1 {
            Issue.record(
                "\(step): rows \(row) and \(next) are not consecutive:\n\(app.screen)", sourceLocation: sourceLocation)
            return
        }
    }

    /// No row between the one showing `top` and the one showing `bottom` is
    /// blank: a control's content has no filler inside it.
    static func expectNoBlankRows(
        _ app: TestApp, from top: String, to bottom: String, _ step: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let lines = app.screen.lines
        guard let first = lines.firstIndex(where: { contains($0, word: top) }),
            let last = lines.lastIndex(where: { contains($0, word: bottom) }), first < last
        else { return }
        for row in (first + 1)..<last where isBlank(lines[row][...]) {
            Issue.record("\(step): row \(row) is blank inside its control:\n\(app.screen)", sourceLocation: sourceLocation)
            return
        }
    }

    /// Whether the screen shows that it has more than it shows: an ellipsis,
    /// or a scroll bar's thumb or track.
    static func showsASign(_ line: String) -> Bool {
        line.contains("…") || line.unicodeScalars.contains { (0x2580...0x259F).contains($0.value) }
            || line.contains("┃") || line.contains("▲") || line.contains("▼")
    }

    /// `text`, where the start of it shows, shows whole, wrapped onto the rows
    /// below, or cut with a sign that it was: never silently cut short.
    static func expectNotSilentlyCut(
        _ app: TestApp, _ text: String, _ step: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let lines = app.screen.lines
        let head = String(text.prefix(3))
        guard let row = lines.firstIndex(where: { $0.contains(head) }) else { return }
        // Read on from the head through the rows below, chrome and spaces
        // dropped, for the rest of the text in order.
        let wanted = text.filter { !$0.isWhitespace }
        var found = wanted.startIndex
        for line in lines[row...].prefix(text.count) {
            let start = line == lines[row] ? line.range(of: head)!.lowerBound : line.startIndex
            for character in line[start...] where !character.isWhitespace && found < wanted.endIndex {
                if character == wanted[found] { found = wanted.index(after: found) }
            }
        }
        if found == wanted.endIndex { return }
        if lines.contains(where: showsASign) { return }
        Issue.record("\(step): \"\(text)\" is cut with no sign:\n\(app.screen)", sourceLocation: sourceLocation)
    }

    /// Takes `step` until `label` shows, checking each frame on the way, and
    /// records an issue when `limit` steps do not bring it.
    @discardableResult
    static func reach(
        _ label: String, in app: TestApp, by step: NavigationStep, limit: Int = 60,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Bool {
        // The wheel stays where it started, as a hand on a mouse does.
        var point: CellPoint?
        if case .wheelDown(let over) = step {
            let (width, height) = app.size
            point = over.flatMap { app.screen.location(of: $0) } ?? CellPoint(x: width / 2, y: height / 2)
        }
        for taken in 0...limit {
            if shows(label, in: app) { return true }
            if taken == limit { break }
            if let point {
                // A tenth of a second a notch, as a hand turns a wheel: what
                // lets a nested scroller's hold at its edge run out, so the
                // wheel chains to the scroll view around it.
                app.scroll(.down, by: 1, at: point)
                app.advance(by: .milliseconds(100))
            } else {
                take(step, in: app)
            }
            check(
                app, "\(step) ×\(taken + 1) toward \(label)", focusMustShow: point == nil,
                sourceLocation: sourceLocation)
        }
        Issue.record("\(limit) × \(step) never brought \(label) on screen:\n\(app.screen)", sourceLocation: sourceLocation)
        return false
    }

    /// Whether `label` shows whole: on one row, or wrapped onto the next as
    /// a narrow column wraps it, the chrome either side of it aside.
    static func shows(_ label: String, in app: TestApp) -> Bool {
        let lines = app.screen.lines
        if lines.contains(where: { contains($0, word: label) }) { return true }
        let content = lines.map { line in
            String(line.unicodeScalars.filter { $0 == " " || !isChrome($0) }.map(Character.init))
                .split(separator: " ").joined(separator: " ")
        }
        return zip(content, content.dropFirst()).contains { contains($0 + " " + $1, word: label) }
    }

    /// Takes one key step.
    static func take(_ step: NavigationStep, in app: TestApp) {
        switch step {
        case .wheelDown: app.scroll(.down, by: 1)
        case .pageDown: app.press(.pageDown)
        case .end: app.press(.end)
        case .tab: app.press(.tab)
        case .down: app.press(.down)
        }
    }
}

extension TestApp {
    /// The terminal's size.
    var size: (width: Int, height: Int) { headless.size }
}
