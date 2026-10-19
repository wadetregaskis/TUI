//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnPlaceTests.swift
//
//  A width a user gives a column with no customization identifier is kept by
//  the table (decisions B-D4T-7), keyed by the column's place in the column
//  closure — so a condition before it, turned on or off, does not hand the
//  width to another column.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTables
@testable import TUIkitTestSupport

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
@Suite("A table keeps a column's width by its place")
struct TableColumnPlaceTests {
    @Test("A width given to a column after an if stays with it when the if adds a column before it")
    func widthStaysWithItsColumn() throws {
        let shown = Shown()
        let app = HeadlessApp(FilesApp(shown), width: 60, height: 14)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func key(_ event: KeyEvent) {
            app.send(event)
            frame()
        }
        var lines: [String] { app.screen.map(\.stripped) }
        func width(of title: String, before next: String) -> Int? {
            guard let line = lines.first(where: { $0.contains(title) && $0.contains(next) }),
                let start = line.range(of: title), let end = line.range(of: next)
            else { return nil }
            return line.distance(from: start.lowerBound, to: end.lowerBound)
        }
        frame()
        frame()

        let kind = try #require(width(of: "Kind", before: "Tail"))
        // Ctrl-K picks the first column, → the next: Kind. Widened by two.
        key(KeyEvent(key: .character("k"), ctrl: true))
        key(KeyEvent(key: .right))
        key(KeyEvent(key: .character("+")))
        key(KeyEvent(key: .character("+")))
        key(KeyEvent(key: .escape))
        let widened = try #require(width(of: "Kind", before: "Tail"))
        #expect(widened == kind + 2, "\(lines.joined(separator: "\n"))")

        shown.size = true
        frame()
        frame()
        #expect(
            width(of: "Kind", before: "Tail") == widened,
            "Kind keeps the width it was given: \(lines.joined(separator: "\n"))")
        // Size, new before it, takes no width it was not given: it shares the
        // room left as Name, declared alike and never resized, does — to the
        // cell the share's remainder gives the first column.
        let name = try #require(width(of: "Name", before: "Size"))
        let size = try #require(width(of: "Size", before: "Kind"))
        #expect(abs(size - name) <= 1, "Size is as wide as Name: \(lines.joined(separator: "\n"))")
    }
}
