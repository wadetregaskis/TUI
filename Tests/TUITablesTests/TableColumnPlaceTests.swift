//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnPlaceTests.swift
//
//  A width a user gives a column with no customization identifier is kept by
//  the table (decisions B-D4T-7), keyed by the column's place in the column
//  closure — so a condition before it, turned on or off, does not hand the
//  width to another column. The table here neither sorts, selects nor is
//  customized, so a drag at the gap after a title, which gives a column a
//  width, has only the table's own handler to take it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITables
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Shown {
    var size = false
}

private struct File: Identifiable, Equatable {
    let id: Int
    var name: String { "n\(id)" }
    var size: String { "s\(id)" }
    var kind: String { "k\(id)" }
    var tail: String { "t\(id)" }
}

private struct FilesApp: App {
    let shown: Shown?

    init() { shown = nil }

    init(_ shown: Shown) { self.shown = shown }

    var body: some Scene {
        WindowGroup {
            Group { if let shown { FilesPage(shown: shown) } }
        }
    }
}

private struct FilesPage: View {
    let shown: Shown
    private let files = (1...3).map(File.init)

    var body: some View {
        Table(files) {
            TableColumn("Name", value: \.name)
            if shown.size {
                TableColumn("Size", value: \.size)
            }
            TableColumn("Kind", value: \.kind)
            TableColumn("Tail", value: \.tail)
        }
        .frame(height: 9)
    }
}

@MainActor
private final class Harness {
    let shown = Shown()
    let app: TestApp
    private var now: Int64 = 0

    init() {
        app = TestApp(FilesApp(shown), width: 60, height: 14)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func key(_ event: KeyEvent) {
        app.send(event)
        frame()
    }

    func send(_ event: MouseEvent) {
        app.send(event)
        frame()
    }

    /// A left-button drag along line `y` from `fromX` to `toX`, a cell at a
    /// time.
    func drag(on y: Int, fromX: Int, toX: Int) {
        send(MouseEvent(button: .left, phase: .pressed, x: fromX, y: y))
        let step = toX > fromX ? 1 : -1
        var x = fromX
        while x != toX {
            x += step
            send(MouseEvent(button: .left, phase: .dragged, x: x, y: y))
        }
        send(MouseEvent(button: .left, phase: .released, x: toX, y: y))
    }

    var lines: [String] { app.screen.lines }

    var screen: String { lines.joined(separator: "\n") }

    /// How far `title` starts on the header before `next` does: its column's
    /// width and the gap after it.
    func width(of title: String, before next: String) -> Int? {
        guard let line = lines.first(where: { $0.contains(title) && $0.contains(next) }),
            let start = line.range(of: title), let end = line.range(of: next)
        else { return nil }
        return line.distance(from: start.lowerBound, to: end.lowerBound)
    }

    /// The header line, by two titles on it.
    func headerY(_ title: String, _ next: String) -> Int? {
        lines.firstIndex { $0.contains(title) && $0.contains(next) }
    }

    func column(of text: String, on y: Int) -> Int? {
        lines[y].range(of: text).map { lines[y].distance(from: lines[y].startIndex, to: $0.lowerBound) }
    }
}

@MainActor
@Suite("A table keeps a column's width by its place")
struct TableColumnPlaceTests {
    @Test("A width given to a column after an if stays with it when the if adds a column before it")
    func widthStaysWithItsColumn() throws {
        let harness = Harness()
        let kind = try #require(harness.width(of: "Kind", before: "Tail"))
        // Ctrl-K picks the first column, → the next: Kind. Widened by two.
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        harness.key(KeyEvent(key: .right))
        harness.key(KeyEvent(key: .character("+")))
        harness.key(KeyEvent(key: .character("+")))
        harness.key(KeyEvent(key: .escape))
        let widened = try #require(harness.width(of: "Kind", before: "Tail"))
        #expect(widened == kind + 2, "\(harness.screen)")

        harness.shown.size = true
        harness.frame()
        harness.frame()
        #expect(
            harness.width(of: "Kind", before: "Tail") == widened,
            "Kind keeps the width it was given: \(harness.screen)")
        // Size, new before it, takes no width it was not given: it shares the
        // room left as Name, declared alike and never resized, does — to the
        // cell the share's remainder gives the first column.
        let name = try #require(harness.width(of: "Name", before: "Size"))
        let size = try #require(harness.width(of: "Size", before: "Kind"))
        #expect(abs(size - name) <= 1, "Size is as wide as Name: \(harness.screen)")
    }

    /// A table that neither sorts, selects nor is customized registers no
    /// title, and its gaps have no region of their own: the header gesture
    /// it hands its own handler is all that makes a gap the edge of a column
    /// (lane LISTSPERF), as on every table (decisions B-D4T-7).
    @Test("On a table that neither sorts, selects nor is customized, dragging the gap after a title resizes that column")
    func plainTableGapDragResizes() throws {
        let harness = Harness()
        let y = try #require(harness.headerY("Name", "Kind"), "\(harness.screen)")
        let name = try #require(harness.width(of: "Name", before: "Kind"))
        let kind = try #require(harness.column(of: "Kind", on: y))
        // The gap is the two cells before Kind: three cells right, Name is
        // three wider.
        harness.drag(on: y, fromX: kind - 1, toX: kind + 2)
        #expect(harness.width(of: "Name", before: "Kind") == name + 3, "\(harness.screen)")
        harness.frame()
        harness.frame()
        #expect(harness.width(of: "Name", before: "Kind") == name + 3, "the width is kept from frame to frame")

        // The gap before Tail is Kind's, found on the frame's header as drawn.
        let kindWidth = try #require(harness.width(of: "Kind", before: "Tail"))
        let tail = try #require(harness.column(of: "Tail", on: y))
        harness.drag(on: y, fromX: tail - 2, toX: tail)
        #expect(harness.width(of: "Kind", before: "Tail") == kindWidth + 2, "\(harness.screen)")
        #expect(harness.width(of: "Name", before: "Kind") == name + 3, "\(harness.screen)")
    }
}
