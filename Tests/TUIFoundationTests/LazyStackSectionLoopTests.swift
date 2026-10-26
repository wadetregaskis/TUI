//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackSectionLoopTests.swift
//
//  `LazyVStack { ForEach(groups) { group in Section { … } } }`, unpinned: the
//  stack keeps each looped section whole, one child per group, so it windows
//  over the sections and builds only those it draws — taken apart, the loop's
//  rows make a number of children only each row knows, and every row of every
//  section was built on every walk (decisions B15, B16; D1S B-D1S-1). Each
//  section lays its parts out as the stack would, so the drawing is the one
//  the stack makes of the same parts taken apart.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// How many sections were built.
@MainActor
private final class Built {
    var sections = 0
}

@MainActor
@Suite("A lazy stack over a loop of sections stays lazy")
struct LazyStackSectionLoopTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 14) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped).map { $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
    }

    @Test("A LazyVStack over a thousand sections builds only the sections it draws")
    func columnStaysLazy() {
        let built = Built()
        func section(_ group: Int) -> some View {
            built.sections += 1
            return Section {
                ForEach(0..<5, id: \.self) { Text("row \(group).\($0)") }
            } header: {
                Text("Group \(group)")
            }
        }
        let drawn = lines(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<1_000, id: \.self) { section($0) } }
            }
            .frame(height: 6),
            height: 6)
        #expect(drawn.first?.hasPrefix("Group 0") == true, "\(drawn)")
        #expect(built.sections < 100, "built \(built.sections) sections to draw one")
    }

    @Test("Each looped section lays its parts out as the stack lays out the same parts taken apart")
    func sameDrawingAsTakenApart() {
        @ViewBuilder
        func parts(_ group: Int) -> some View {
            Text("head \(group)")
            Text("a\(group)")
            Text("bb\(group)")
        }
        for alignment in [HorizontalAlignment.leading, .trailing] {
            let lazy = lines(
                LazyVStack(alignment: alignment, spacing: 1) {
                    ForEach(0..<2, id: \.self) { group in
                        Section {
                            Text("a\(group)")
                            Text("bb\(group)")
                        } header: {
                            Text("head \(group)")
                        }
                    }
                })
            let eager = lines(
                VStack(alignment: alignment, spacing: 1) { ForEach(0..<2, id: \.self) { parts($0) } })
            #expect(lazy == eager, "\(alignment): \(lazy) vs \(eager)")
        }
        let row = lines(
            LazyHStack(spacing: 1) {
                ForEach(0..<2, id: \.self) { group in
                    Section { Text("a\(group)") } header: { Text("h\(group)") }
                }
            })
        #expect(row.first == "h0 a0 h1 a1")
    }

    @Test("A section written in the stack's content, not made by a loop, is still its parts")
    func writtenSectionIsItsParts() {
        let drawn = lines(
            LazyVStack(alignment: .leading, spacing: 1) {
                Text("x")
                if true {
                    Section {
                        Text("a")
                        Text("b")
                    } header: {
                        Text("h")
                    }
                }
            })
        #expect(Array(drawn.prefix(7)) == ["x", "", "h", "", "a", "", "b"])
    }
}
