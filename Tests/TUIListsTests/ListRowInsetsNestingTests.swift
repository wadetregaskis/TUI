//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowInsetsNestingTests.swift
//
//  `listRowInsets` written twice on one row added the two up, where SwiftUI's
//  inner statement replaces the outer one on the edges both name: a row's
//  insets are one setting, not a stack of paddings. A SwiftUI program that
//  sets a default on a row and overrides it closer in got doubled insets.
//  Edges only one of them names keep that one's inset (coordinator's call,
//  2026-11-08; the deviations doc's V6 row is gone).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
@Suite("listRowInsets written twice")
struct ListRowInsetsNestingTests {

    private func lines(_ view: some View, width: Int = 20, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    @Test("The inner insets replace the outer ones")
    func innerReplacesOuter() {
        let twice = lines(
            Text("row").listRowInsets(EdgeInsets(horizontal: 2, vertical: 0))
                .listRowInsets(EdgeInsets(horizontal: 5, vertical: 1)))
        #expect(twice == lines(Text("row").listRowInsets(EdgeInsets(horizontal: 2, vertical: 0))), "\(twice)")
    }

    @Test("Only the edges both name are replaced")
    func sharedEdgesOnly() {
        let twice = lines(Text("row").listRowInsets(.leading, 2).listRowInsets(.all, 1))
        let once = lines(Text("row").listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 1)))
        #expect(twice == once, "\(twice) against \(once)")
    }

    @Test("Through a modifier between them as well")
    func throughAModifier() {
        let twice = lines(
            Text("row").listRowInsets(.leading, 2).foregroundStyle(.red).listRowInsets(.leading, 6))
        #expect(twice.first?.hasPrefix("  row") == true, "\(twice)")
        #expect(twice.first?.hasPrefix("   ") == false, "\(twice)")
    }

    @Test("An inner nil sets the default on every edge, over the outer insets")
    func innerNilIsTheDefault() {
        #expect(lines(Text("row").listRowInsets(nil).listRowInsets(.leading, 4)) == lines(Text("row")))
    }
}
