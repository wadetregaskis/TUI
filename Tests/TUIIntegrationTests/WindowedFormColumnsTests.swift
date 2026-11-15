//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedFormColumnsTests.swift
//
//  SCROLL-FIT P8's leftover (design §1c): a `.columns` form of a long loop
//  in scroll content builds only the rows on screen, its label column and
//  rows' width read once from every row and kept while its data is the same,
//  and draws what the same form drawn whole draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class FormBuilds {
    var count = 0
}

@MainActor
@Suite("SCROLL-FIT P8: a long .columns Form builds only the rows on screen")
struct WindowedFormColumnsTests {
    /// A row's label: short, but the widest one far down the loop, past any
    /// sample a band could take, so the label column is every row's.
    private static func label(_ index: Int, count: Int) -> String {
        index == count - 3 ? "a much longer key" : "k\(index % 5)"
    }

    /// A form of `count` labelled rows under a title and over a footer in
    /// scroll content; drawn `whole`, every row built each frame, as before.
    private static func app(
        rows count: Int, builds: FormBuilds, whole: Bool = false, fitsContent: Bool = false
    ) -> TestApp {
        TestApp(width: 40, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    Form {
                        ForEach(0..<count, id: \.self) { index in
                            builds.count += 1
                            return LabeledContent(label(index, count: count), value: "v\(index)")
                        }
                    }
                    .formStyle(.columns)
                    Text("footer")
                }
            }
            .environment(\.drawsContainerRowsWhole, whole)
            .environment(\.scrollFitsContent, fitsContent)
        }
    }

    /// The screen but its scrollbar's column: the thumb reads the windowed
    /// column's estimated height, the eager one's exact one.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 40)).prefix(39)) }
    }

    @Test("A windowed form draws what the form drawn whole draws, at the top, paged, wheeled and at the end",
          arguments: [false, true])
    func drawsWhatTheEagerOneDraws(fitsContent: Bool) {
        let lazy = Self.app(rows: 300, builds: FormBuilds(), fitsContent: fitsContent)
        let eager = Self.app(rows: 300, builds: FormBuilds(), whole: true, fitsContent: fitsContent)
        func check(_ step: String) {
            #expect(Self.content(lazy) == Self.content(eager), "\(step):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
        check("top")
        for page in 1...3 {
            _ = lazy.press(.pageDown)
            _ = eager.press(.pageDown)
            check("page \(page)")
        }
        for tick in 1...3 {
            lazy.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5))
            eager.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5))
            check("wheel \(tick)")
        }
        _ = lazy.press(.end)
        _ = eager.press(.end)
        check("end")
        _ = lazy.press(.home)
        _ = eager.press(.home)
        check("home")
    }

    /// The rows built on the first frame and on each of five page-downs.
    private static func builtPerStep(rows: Int, fitsContent: Bool) -> [Int] {
        let builds = FormBuilds()
        let app = app(rows: rows, builds: builds, fitsContent: fitsContent)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<5 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    /// The first frame reads every row once at each width the form is laid
    /// out at, for the label column and the rows' width (20,177 rows at
    /// 10,000: two widths); a page builds fewer than 100 rows, the same
    /// around 2,000 rows as around 10,000. (Before, every row several times
    /// a frame: 50,000 a page at 10,000.)
    @Test("Around 10,000 rows, a page builds fewer than 100 rows, the same as around 2,000",
          arguments: [false, true])
    func builtRowsIndependentOfRowCount(fitsContent: Bool) {
        let tenThousand = Self.builtPerStep(rows: 10_000, fitsContent: fitsContent)
        let twoThousand = Self.builtPerStep(rows: 2_000, fitsContent: fitsContent)
        #expect(tenThousand.dropFirst().allSatisfy { $0 < 100 }, "\(tenThousand)")
        #expect(tenThousand.dropFirst() == twoThousand.dropFirst(), "\(twoThousand) \(tenThousand)")
        #expect(tenThousand[0] < 3 * 10_000, "\(tenThousand)")
    }

    @Test("Around 10,000 rows, End shows the last row and the footer, its label in the one column")
    func endReachesTheLastRow() {
        let app = Self.app(rows: 10_000, builds: FormBuilds())
        _ = app.press(.end)
        let screen = app.screen
        #expect(screen.contains("v9999") && screen.contains("footer"), "\(screen)")
        // The last row's value in the column the widest label, three rows
        // up, puts every value in.
        func valueColumn(_ value: String) -> Int? {
            screen.lines.lazy.compactMap { line in
                line.range(of: value).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
            }.first
        }
        #expect(screen.contains("a much longer key"), "\(screen)")
        #expect(valueColumn("v9999") != nil && valueColumn("v9999") == valueColumn("v9997"), "\(screen)")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(app.screen)")
    }

    /// The kept label column is the data's: a loop that changes draws as the
    /// changed loop drawn whole does, its widest label read again.
    @Test("A change of the loop's data reads the label column again")
    func changedDataReadsTheColumnAgain() {
        let rows = FormRows(count: 300)
        func app(whole: Bool) -> TestApp {
            TestApp(width: 40, height: 12) {
                ScrollView {
                    Form {
                        ForEach(0..<rows.count, id: \.self) { index in
                            LabeledContent(index == 297 ? "a much longer key" : "k\(index % 5)", value: "v\(index)")
                        }
                    }
                    .formStyle(.columns)
                }
                .environment(\.drawsContainerRowsWhole, whole)
            }
        }
        let lazy = app(whole: false)
        let eager = app(whole: true)
        #expect(Self.content(lazy) == Self.content(eager), "\(lazy.screen)\n---\n\(eager.screen)")
        // Past the threshold still, the widest label gone with the rows
        // that held it.
        rows.count = 290
        #expect(Self.content(lazy) == Self.content(eager), "\(lazy.screen)\n---\n\(eager.screen)")
    }
}

/// How many rows a form's loop has, changed by a test.
@Observable
@MainActor
private final class FormRows {
    var count: Int

    init(count: Int) { self.count = count }
}
