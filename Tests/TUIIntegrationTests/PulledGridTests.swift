//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledGridTests.swift
//
//  SCROLL-FIT and `Grid` (design §1c, P8): a grid stays eager, as SwiftUI's
//  does, since it has a lazy counterpart. A lazy stack in one of its cells,
//  and a grid among the children of a pulled column, are each placed where
//  the same rows drawn eagerly are, at the top, paged and at the end.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

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
    private static func rows(_ count: Int, lazy: Bool) -> some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { Text(label($0)) }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { Text(label($0)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func app(_ shape: Shape, lazy: Bool) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    switch shape {
                    case .stackInCell:
                        Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 0) {
                            GridRow {
                                Text("|")
                                rows(300, lazy: lazy)
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
                        rows(300, lazy: lazy)
                    }
                    Text("footer")
                }
            }
        }
    }

    /// The screen but its scrollbar's column, which reads the lazy stack's
    /// estimated height.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    @Test("Drawn as the same rows drawn eagerly, at the top, paged, wheeled and at the end",
          arguments: Shape.allCases)
    func drawsWhatTheEagerOneDraws(_ shape: Shape) {
        let lazy = Self.app(shape, lazy: true)
        let eager = Self.app(shape, lazy: false)
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
}
