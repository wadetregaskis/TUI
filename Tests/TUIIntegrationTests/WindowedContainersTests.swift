//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedContainersTests.swift
//
//  SCROLL-FIT P8 (design §1c, A-SCROLLFIT-1): a container with no lazy
//  counterpart in SwiftUI — `GroupBox`, `DisclosureGroup`, a `Section` drawn
//  as one view — directly around a `ForEach` of more rows than a lazy stack
//  draws whole builds only the rows on screen in scroll content, whatever its
//  row count, draws what the same rows in an eager `VStack` draw, and still
//  reaches every row. A `FlowLayout` of as many items draws its lines so.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds {
    var count = 0
}

@MainActor
@Suite("SCROLL-FIT P8: containers with no lazy counterpart build only the rows on screen")
struct WindowedContainersTests {
    enum Shape: String, CaseIterable, Sendable {
        case groupBox, titledGroupBox, disclosureGroup, section, flow
    }

    /// A row's text: two lines every third row in a column; in a flow, words
    /// of one to four letters after the number, so lines break unevenly.
    private static func label(_ index: Int, shape: Shape) -> String {
        if shape == .flow { return "a\(index)" + String(repeating: "x", count: index % 4) }
        return index.isMultiple(of: 3) ? "a\(index)\n  more" : "a\(index)"
    }

    /// The rows, as the container's whole content. Drawn `whole`, each fills
    /// the column's width, as the rows of a windowed column are drawn: a
    /// column drawn whole hugs its widest row, which only every row measured
    /// can say (`windowedColumnSize`). A flow's items keep their own widths.
    @ViewBuilder
    private static func rows(_ count: Int, shape: Shape, builds: Builds, whole: Bool = false) -> some View {
        if whole, shape != .flow {
            ForEach(0..<count, id: \.self) { index in
                Text(label(index, shape: shape)).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(0..<count, id: \.self) { index in
                builds.count += 1
                return Text(label(index, shape: shape))
            }
        }
    }

    @ViewBuilder
    private static func wrapped<Rows: View>(_ shape: Shape, _ rows: () -> Rows) -> some View {
        switch shape {
        case .groupBox: GroupBox { rows() }
        case .titledGroupBox: GroupBox("Box") { rows() }
        case .disclosureGroup: disclosure(rows())
        case .section: rows()
        case .flow: flow(rows())
        }
    }

    private static func disclosure<Rows: View>(_ rows: Rows) -> some View {
        DisclosureGroup("More", isExpanded: .constant(true)) { rows }
    }

    private static func flow<Rows: View>(_ rows: Rows) -> some View {
        FlowLayout(spacing: 1) { rows }
    }

    /// `rows` in `shape` under a title and over a footer in scroll content;
    /// drawn `whole`, every row built, as before SCROLL-FIT P8: the twin the
    /// windowed drawing must match.
    private static func app(_ shape: Shape, rows count: Int, builds: Builds, whole: Bool = false) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                // A section in a stack is taken apart, its rows the stack's
                // own: drawn as one view, as a scroll view's content, its
                // header and footer stand for the title and the footer.
                if shape == .section {
                    Section {
                        rows(count, shape: shape, builds: builds, whole: whole)
                    } header: {
                        Text("title")
                    } footer: {
                        Text("footer")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("title")
                        wrapped(shape) { rows(count, shape: shape, builds: builds, whole: whole) }
                        Text("footer")
                    }
                }
            }
            .environment(\.drawsContainerRowsWhole, whole)
        }
    }

    /// The screen but its scrollbar's column: the thumb reads the windowed
    /// column's estimated height, the eager one's exact one.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    @Test("A windowed container draws what the eager one draws, at the top, paged, wheeled and at the end",
          arguments: Shape.allCases)
    func drawsWhatTheEagerOneDraws(_ shape: Shape) {
        let lazy = Self.app(shape, rows: 300, builds: Builds())
        let eager = Self.app(shape, rows: 300, builds: Builds(), whole: true)
        func check(_ step: String) {
            #expect(Self.content(lazy) == Self.content(eager), "\(shape) \(step):\n\(lazy.screen)\n---\n\(eager.screen)")
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
        for tick in 1...3 {
            lazy.scroll(.up, by: 1, at: CellPoint(x: 5, y: 5))
            eager.scroll(.up, by: 1, at: CellPoint(x: 5, y: 5))
            check("wheel back \(tick)")
        }
        _ = lazy.press(.home)
        _ = eager.press(.home)
        check("home")
    }

    /// The rows built on the first frame and on each of five page-downs.
    private static func builtPerStep(_ shape: Shape, rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(shape, rows: rows, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<5 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    /// A page step builds fewer than 100 rows, the same around 2,000 rows as
    /// around 10,000. A first frame builds a screenful and the measure
    /// ladder's sixteen-row samples, as a lazy stack's does (pinned under 150
    /// in `ScrollFitBaselineTests`); a disclosure group's also the rows its
    /// focused button's continuation probe looks through (`focusRingStops`),
    /// bounded whatever the count. A flow's first frame measures every item
    /// to break its lines (A-SCROLLFIT-5 (a)); its steps measure none again.
    /// (Before P8, every row on every frame: 10,000 a step.)
    @Test("Around 10,000 rows, a page builds fewer than 100 rows, the same as around 2,000",
          arguments: Shape.allCases)
    func builtRowsIndependentOfRowCount(_ shape: Shape) {
        let tenThousand = Self.builtPerStep(shape, rows: 10_000)
        let twoThousand = Self.builtPerStep(shape, rows: 2_000)
        #expect(tenThousand.dropFirst().allSatisfy { $0 < 100 }, "\(shape): \(tenThousand)")
        #expect(tenThousand.dropFirst() == twoThousand.dropFirst(), "\(shape): \(twoThousand) \(tenThousand)")
        if shape == .flow {
            #expect(tenThousand[0] < 4 * 10_000, "\(shape): \(tenThousand)")
        } else {
            #expect(tenThousand[0] < 150 && tenThousand[0] == twoThousand[0], "\(shape): \(twoThousand) \(tenThousand)")
        }
    }

    @Test("Around 10,000 rows, End shows the last row and the footer; Home brings the title back",
          arguments: Shape.allCases)
    func endReachesTheLastRow(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 10_000, builds: builds)
        _ = app.press(.end)
        #expect(app.screen.contains("a9999"), "\(shape): \(app.screen)")
        #expect(app.screen.contains("footer"), "\(shape): \(app.screen)")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(shape): \(app.screen)")
    }

    @Test("Paging reaches every row, in order", arguments: Shape.allCases)
    func pagingReachesEveryRow(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 400, builds: builds)
        var seen = Set<Int>()
        func collect() {
            for line in app.screen.lines {
                for match in line.matches(of: /a(\d+)/) { if let row = Int(match.1) { seen.insert(row) } }
            }
        }
        collect()
        for _ in 0..<80 {
            _ = app.press(.pageDown)
            collect()
        }
        let missing = (0..<400).filter { !seen.contains($0) }
        #expect(missing.isEmpty, "\(shape): \(missing.count) rows never drawn: \(missing.prefix(10))")
    }

    /// At or below the lazy stack's threshold every row is built, as SwiftUI
    /// builds an eager container's: the window starts past it.
    @Test("Up to 256 rows, every row is built", arguments: Shape.allCases)
    func smallContainerBuildsEveryRow(_ shape: Shape) {
        let builds = Builds()
        let app = Self.app(shape, rows: 256, builds: builds)
        _ = app.screen
        #expect(builds.count >= 256, "\(shape): \(builds.count)")
    }
}
