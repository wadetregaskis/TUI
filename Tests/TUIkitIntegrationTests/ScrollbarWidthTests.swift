//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarWidthTests.swift
//
//  `.scrollbarWidth(_:)`: a vertical scrollbar two cells wide, on every
//  scrolling view that draws one — the same bar side by side, its arrows
//  doubled, its content a cell narrower, the whole width taking the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Double-width vertical scrollbars")
struct ScrollbarWidthTests {

    private static let items = (0..<30).map { "item \($0)" }

    private struct Row: Identifiable {
        let id: Int
        let name: String
    }

    enum Site: CaseIterable, Sendable {
        case scrollView, list, table
    }

    @ViewBuilder
    private func view(_ site: Site) -> some View {
        switch site {
        case .scrollView:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.items, id: \.self) { Text($0) }
                }
            }
            .scrollIndicators(.visible)
        case .list:
            List(Self.items, id: \.self) { Text($0) }.scrollIndicators(.visible)
        case .table:
            Table((0..<30).map { Row(id: $0, name: "row \($0)") }) {
                TableColumn("Name", value: \Row.name)
            }
            .scrollIndicators(.visible)
        }
    }

    /// The glyphs that draw an up arrow: one cell's `▲`, or the halves of one
    /// triangle across two cells.
    private static let upArrowGlyphs: Set<Character> = ["▲", "◢", "◣"]

    /// The columns the bar's up-arrow cells take on the line it is on.
    private func arrowColumns(_ buffer: FrameBuffer) -> [Int] {
        guard let line = buffer.lines.map(\.stripped).first(where: { $0.contains(where: Self.upArrowGlyphs.contains) })
        else { return [] }
        return Array(line).enumerated().filter { Self.upArrowGlyphs.contains($0.element) }.map(\.offset)
    }

    /// The up arrow's glyphs on the line it is on, left to right.
    private func upArrow(_ buffer: FrameBuffer) -> String {
        guard let line = buffer.lines.map(\.stripped).first(where: { $0.contains(where: Self.upArrowGlyphs.contains) })
        else { return "" }
        return String(line.filter(Self.upArrowGlyphs.contains))
    }

    @Test("A double-width bar's arrow is one triangle across both cells, or two arrows where the terminal cannot",
        arguments: Site.allCases)
    func arrowGlyphs(_ site: Site) {
        // FB6 (owner): `◢◣` / `◥◤` by default; `▲▲` / `▼▼` on a terminal that
        // draws the triangles from its font, short of the cells' edges.
        let triangles = renderToBuffer(
            view(site).scrollbarWidth(2), context: makeRenderContext(width: 30, height: 10))
        #expect(upArrow(triangles) == "◢◣", "\(site): \(triangles.lines.map(\.stripped))")
        #expect(triangles.lines.map(\.stripped).contains { $0.contains("◥◤") }, "\(site): the down arrow")
        let doubled = renderToBuffer(
            view(site).scrollbarWidth(2).environment(\.cornerTrianglesFillTheCell, false),
            context: makeRenderContext(width: 30, height: 10))
        #expect(upArrow(doubled) == "▲▲", "\(site): \(doubled.lines.map(\.stripped))")
        let single = renderToBuffer(view(site), context: makeRenderContext(width: 30, height: 10))
        #expect(upArrow(single) == "▲", "\(site): a one-cell bar keeps its arrow")
    }

    @Test("Two cells wide: the arrows doubled side by side, the bar still against the same edge",
        arguments: Site.allCases)
    func doubleWidth(_ site: Site) {
        let single = renderToBuffer(view(site), context: makeRenderContext(width: 30, height: 10))
        let double = renderToBuffer(
            view(site).scrollbarWidth(2), context: makeRenderContext(width: 30, height: 10))
        let one = arrowColumns(single)
        let two = arrowColumns(double)
        #expect(one.count == 1, "\(site): a single bar: \(single.lines.map(\.stripped))")
        #expect(two.count == 2, "\(site): a double bar: \(double.lines.map(\.stripped))")
        guard let last = one.last, two.count == 2 else { return }
        #expect(two == [last - 1, last], "\(site): the bar's right edge stays where it was")
        #expect(single.width == double.width, "\(site): the view is no wider")
    }

    @Test("The width is one or two, whatever is asked")
    func clamped() {
        let three = renderToBuffer(
            view(.scrollView).scrollbarWidth(3), context: makeRenderContext(width: 30, height: 10))
        #expect(arrowColumns(three).count == 2)
        let none = renderToBuffer(
            view(.scrollView).scrollbarWidth(0), context: makeRenderContext(width: 30, height: 10))
        #expect(arrowColumns(none).count == 1)
    }
}
