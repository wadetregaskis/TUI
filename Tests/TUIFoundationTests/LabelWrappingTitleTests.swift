//  🖥️ TUI — A Terminal UI framework for Swift
//  LabelWrappingTitleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// SwiftUI's default label centres its icon on the FIRST line of its title,
/// not on the whole title: a title that wraps keeps its icon beside its first
/// line, and a one-line title beside a tall icon sits at the icon's middle
/// (measured, `Tools/SwiftUIProbes/Labels beside wrapping text`). Centring on
/// the block put the icon beside the middle of a wrapped title.
@MainActor
@Suite("A label's icon sits beside its title's first line")
struct LabelWrappingTitleTests {

    private func lines(_ view: some View, width: Int) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: 12)).lines.map { line in
            var text = line.stripped
            while text.last == " " { text.removeLast() }
            return text
        }
    }

    /// A one-row icon drawn as a letter, so its row can be read back.
    private func icon(_ rows: [String]) -> some View {
        VStack(spacing: 0) { ForEach(rows, id: \.self) { Text(verbatim: $0) } }
    }

    @Test("A wrapping title keeps a one-row icon beside its first line")
    func iconBesideFirstLine() {
        let drawn = lines(Label { Text(verbatim: "aa bb cc") } icon: { icon(["I"]) }, width: 4)
        #expect(drawn == ["I aa", "  bb", "  cc"], "\(drawn)")
    }

    @Test("A one-line title sits at the middle of a tall icon")
    func titleAtTallIconsMiddle() {
        let drawn = lines(Label { Text(verbatim: "T") } icon: { icon(["a", "b", "c"]) }, width: 10)
        #expect(drawn == ["a", "b T", "c"], "\(drawn)")
    }

    @Test("A wrapping title starts at the middle of a tall icon")
    func wrappingTitleAtTallIconsMiddle() {
        let drawn = lines(Label { Text(verbatim: "aa bb cc dd") } icon: { icon(["a", "b", "c"]) }, width: 4)
        #expect(drawn == ["a", "b aa", "c bb", "  cc", "  dd"], "\(drawn)")
    }
}
