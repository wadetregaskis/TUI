//  🖥️ TUI — A Terminal UI framework for Swift
//  EndlessLazyStackAppTests.swift
//
//  SwiftUI's endless-list idiom in a running app:
//  `ScrollView { LazyVStack { ForEach(0..<Int.max, id: \.self) { … } } }`.
//  The stack's own estimate of the rows it has not drawn is held short of
//  overflow (H-12); these drive the run loop's own frames, the measuring walk
//  of an app's first frame included (`RenderLoop.prepareWindowChrome`), and
//  count the rows the loop reads. That walk built every row of the loop to
//  draw the screenful its scroll view gave it, which for `0..<Int.max` is an
//  array of `Int.max` children and a trap: so the count stands in for the
//  trap, over ten million rows, each read through an element the loop reads.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// How many elements of a ``CountedRows`` have been read.
private final class ElementReads: @unchecked Sendable {
    var count = 0
}

/// `0..<count` as a collection that counts its element reads: a `ForEach`
/// over it builds a row's child, or reads a row's key, through one read, so
/// a walk that builds every row reads every element.
private struct CountedRows: RandomAccessCollection {
    let count: Int
    let reads: ElementReads

    var startIndex: Int { 0 }
    var endIndex: Int { count }

    subscript(position: Int) -> Int {
        reads.count += 1
        return position
    }
}

/// The idiom over `rows`, of rows of `lines` lines.
private struct EndlessPage: View {
    let rows: CountedRows
    let lines: Int

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.self) { index in
                    Text(verbatim: lines == 1 ? "row \(index)" : "row \(index)\nsecond")
                }
            }
        }
    }
}

/// An app of the idiom over ten million rows, its frames driven one at a
/// time, each frame's element reads counted.
@MainActor
private final class EndlessDriver {
    static let rowCount = 10_000_000
    static let width = 30
    static let height = 10

    let reads = ElementReads()
    let app: TestApp
    private var now: Int64 = 0
    /// The most elements any frame since the driver was made has read.
    private(set) var mostReads = 0

    init(lines: Int) {
        let rows = CountedRows(count: Self.rowCount, reads: reads)
        app = TestApp(width: Self.width, height: Self.height) { EndlessPage(rows: rows, lines: lines) }
    }

    /// Delivers `event`, if any, and draws the next frame.
    func frame(_ event: KeyEvent? = nil, mouse: MouseEvent? = nil) {
        reads.count = 0
        if let event { _ = app.send(event) }
        if let mouse { _ = app.send(mouse) }
        now += 16_666_667
        app.frame(atNanos: now)
        mostReads = max(mostReads, reads.count)
    }

    /// The row at the top of the screen, from its "row N" line.
    var topRow: Int? {
        app.screen.lines.lazy.compactMap { line -> Int? in
            guard let range = line.range(of: "row ") else { return nil }
            return Int(line[range.upperBound...].prefix { $0.isNumber })
        }.first
    }
}

@MainActor
@Suite("SwiftUI's endless lazy stack in a running app")
struct EndlessLazyStackAppTests {
    /// The most element reads a frame of a 10-line screen may take: the rows
    /// drawn, the window's margin around them, the measure's samples and a
    /// key read or two for each, with room to spare, and nowhere near the
    /// rows. Measured (2026-11-22): at most 278, on the first frame, and under
    /// 80 on every frame after it; 10,000,254 on the first frame before the
    /// measuring walk built only what it drew.
    static let readsPerFrame = 1_000

    @Test("The first frames read only the rows on the screen and around it", arguments: [1, 2])
    func firstFramesAreWindowed(lines: Int) {
        let driver = EndlessDriver(lines: lines)
        for _ in 0..<3 { driver.frame() }
        #expect(driver.mostReads < Self.readsPerFrame, "a frame read \(driver.mostReads) elements")
        #expect(driver.topRow == 0, "\(driver.app.screen.lines)")
    }

    @Test("End, Page Down and Home reach their rows reading only a window's worth", arguments: [1, 2])
    func keysAreWindowed(lines: Int) {
        let driver = EndlessDriver(lines: lines)
        driver.frame()
        driver.frame(KeyEvent(key: .pageDown))
        let paged = driver.topRow ?? -1
        #expect(paged > 0 && paged <= EndlessDriver.height, "Page Down: \(driver.app.screen.lines)")
        driver.frame(KeyEvent(key: .end))
        driver.frame()
        let last = EndlessDriver.rowCount - 1
        #expect(
            driver.app.screen.lines.contains { $0.contains("row \(last)") }, "End: \(driver.app.screen.lines)")
        driver.frame(KeyEvent(key: .home))
        driver.frame()
        #expect(driver.topRow == 0, "Home: \(driver.app.screen.lines)")
        #expect(driver.mostReads < Self.readsPerFrame, "a frame read \(driver.mostReads) elements")
    }

    @Test("A scrollbar drag lands in the middle reading only a window's worth")
    func scrollbarDragIsWindowed() {
        let driver = EndlessDriver(lines: 1)
        driver.frame()
        driver.frame()
        // The bar's last column; at the top its thumb, a cell at ten million
        // rows, sits under the up arrow.
        let bar = EndlessDriver.width - 1
        driver.frame(mouse: MouseEvent(button: .left, phase: .pressed, x: bar, y: 1))
        driver.frame(mouse: MouseEvent(button: .left, phase: .dragged, x: bar, y: EndlessDriver.height / 2))
        driver.frame(mouse: MouseEvent(button: .left, phase: .released, x: bar, y: EndlessDriver.height / 2))
        driver.frame()
        let top = driver.topRow ?? -1
        let rows = EndlessDriver.rowCount
        #expect(top > rows / 4 && top < rows * 3 / 4, "the drag: \(driver.app.screen.lines)")
        #expect(driver.mostReads < Self.readsPerFrame, "a frame read \(driver.mostReads) elements")
    }
}
