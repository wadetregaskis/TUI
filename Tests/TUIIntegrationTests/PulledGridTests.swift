//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledGridTests.swift
//
//  SCROLL-FIT and `Grid` (design §1c, P8): a grid stays eager, as SwiftUI's
//  does, since it has a lazy counterpart. A lazy stack in one of its cells is
//  pulled through the grid's places (`GridCore+Pulled.swift`), building only
//  the rows on screen, and a grid among the children of a pulled column is
//  drawn whole; each is placed where the same rows drawn eagerly are, at the
//  top, paged and at the end.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class GridBuilds {
    var count = 0
}

@MainActor
@Suite("SCROLL-FIT: a Grid stays eager, and what it holds or stands beside is placed as drawn eagerly")
struct PulledGridTests {
    enum Shape: String, CaseIterable, Sendable {
        /// A lazy stack in a grid's cell, beside a gutter.
        case stackInCell
        /// A grid of a few rows between a title and a lazy stack.
        case gridAbovePulledStack
    }

    private static func label(_ index: Int) -> String {
        index.isMultiple(of: 3) ? "a\(index)\n  more" : "a\(index)"
    }

    @ViewBuilder
    private static func rows(_ count: Int, lazy: Bool, builds: GridBuilds = GridBuilds()) -> some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    builds.count += 1
                    return Text(label(index))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { Text(label($0)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func app(
        _ shape: Shape, lazy: Bool, rows count: Int = 300, builds: GridBuilds = GridBuilds(), fitsContent: Bool = false
    ) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    switch shape {
                    case .stackInCell:
                        Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 0) {
                            GridRow {
                                Text("|")
                                rows(count, lazy: lazy, builds: builds)
                            }
                            GridRow {
                                Text("+")
                                Text("below")
                            }
                        }
                    case .gridAbovePulledStack:
                        Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 0) {
                            GridRow { Text("k1"); Text("value one") }
                            GridRow { Text("key2"); Text("v2") }
                        }
                        rows(count, lazy: lazy, builds: builds)
                    }
                    Text("footer")
                }
            }
            .environment(\.scrollFitsContent, fitsContent)
        }
    }

    /// The screen but its scrollbar's column, which reads the lazy stack's
    /// estimated height.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    /// With SCROLL-FIT's switch on too (`scrollFitsContent`), as P7 makes
    /// the default.
    @Test("Drawn as the same rows drawn eagerly, at the top, paged, wheeled and at the end",
          arguments: Shape.allCases, [false, true])
    func drawsWhatTheEagerOneDraws(_ shape: Shape, fitsContent: Bool) {
        let lazy = Self.app(shape, lazy: true, fitsContent: fitsContent)
        let eager = Self.app(shape, lazy: false, fitsContent: fitsContent)
        func check(_ step: String) {
            #expect(Self.content(lazy) == Self.content(eager), "\(shape) \(step):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
        check("top")
        for page in 1...4 {
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
    private static func builtPerStep(_ shape: Shape, rows: Int, fitsContent: Bool) -> [Int] {
        let builds = GridBuilds()
        let app = app(shape, lazy: true, rows: rows, builds: builds, fitsContent: fitsContent)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<5 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    /// A lazy stack in a cell is pulled through the grid: a first frame
    /// builds a screenful and the measure ladder's samples (171 rows here,
    /// against a lazy stack alone's 124), a page fewer than 100 rows, each
    /// the same around 2,000 rows as around 10,000. (Before, drawn whole in its cell: 64,119 rows on the first
    /// frame at 10,000.)
    @Test("A lazy stack in a cell builds the same few rows a page around 2,000 rows as around 10,000",
          arguments: [false, true])
    func stackInCellBuildsOnlyTheRowsOnScreen(fitsContent: Bool) {
        let tenThousand = Self.builtPerStep(.stackInCell, rows: 10_000, fitsContent: fitsContent)
        let twoThousand = Self.builtPerStep(.stackInCell, rows: 2_000, fitsContent: fitsContent)
        #expect(tenThousand.dropFirst().allSatisfy { $0 < 100 }, "\(tenThousand)")
        #expect(tenThousand.dropFirst() == twoThousand.dropFirst(), "\(twoThousand) \(tenThousand)")
        #expect(tenThousand[0] < 250 && tenThousand[0] == twoThousand[0], "\(twoThousand) \(tenThousand)")
    }

    @Test("Around 10,000 rows in a cell, End shows the last row and what is below the grid; Home the title")
    func stackInCellEndReachesTheLastRow() {
        let app = Self.app(.stackInCell, lazy: true, rows: 10_000)
        _ = app.press(.end)
        #expect(app.screen.contains("a9999"), "\(app.screen)")
        #expect(app.screen.contains("below") && app.screen.contains("footer"), "\(app.screen)")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(app.screen)")
    }
}
