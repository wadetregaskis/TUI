//  🖥️ TUI — A Terminal UI framework for Swift
//  TableSelectionMarkTests.swift
//
//  A `Table` left to decide draws its selection mark where colour can't be
//  relied on: at no colour, and under Differentiate Without Colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUILists

@MainActor
@Suite("A Table's selection mark")
struct TableSelectionMarkTests {
    private func resolved(differentiating: Bool, depth: ColorDepth) -> Visibility {
        var environment = EnvironmentValues()
        environment._accessibilityDifferentiateWithoutColor = differentiating
        let context = RenderContext(availableWidth: 20, availableHeight: 4, environment: environment)
        return ColorDepth.withCurrent(depth) {
            RowSelectionIndicator.resolvingForTable(context).environment.rowSelectionIndicator
        }
    }

    @Test("Hidden over colours, shown at no colour and under Differentiate Without Colour")
    func markFollowsTheGate() {
        #expect(resolved(differentiating: false, depth: .truecolor) == .hidden)
        #expect(resolved(differentiating: false, depth: .noColor) == .visible)
        #expect(resolved(differentiating: true, depth: .truecolor) == .visible)
    }
}
