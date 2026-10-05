//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SubviewLayoutTraitsTests.swift
//
//  A `Subview` placed in a container lays out as the view it stands for: a
//  `Spacer` through `ForEach(subviews:)` is a spacer, a member's
//  `.alignmentGuide` moves the proxy, its `.zIndex` orders it in a `ZStack`, and
//  its `.layoutValue` reaches the `Layout` it is placed in — each as SwiftUI
//  does (measured on macOS 15.8, probes in the session notes, `D1S/probe/b17`,
//  `z` and `lv`). The oracle throughout is the same content placed directly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A spacer between two words, with an optional minimum length — a `Group`,
/// whose members are its views (a view of the app's own is one member here).
@MainActor
private func spacedWords(minLength: Int? = nil) -> some View {
    Group {
        Text("a")
        Spacer(minLength: minLength)
        Text("b")
    }
}

/// Three rows, the second hanging two cells left of the leading line and the
/// third with a centre guide at its leading edge.
@MainActor
private func guidedRows() -> some View {
    Group {
        Text("wide row")
        Text("b").alignmentGuide(.leading) { _ in -2 }
        Text("c").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
    }
}

/// Two words in one cell, the first raised above the second.
@MainActor
private func layeredWords() -> some View {
    Group {
        Text("top").zIndex(1)
        Text("low")
    }
}

/// The layout value a `Layout` reads off its subviews.
private struct Rank: LayoutValueKey {
    static let defaultValue = -1
}

/// Writes each subview's rank into a shared list.
@MainActor
private final class RankLog {
    var ranks: [Int] = []
}

private struct RankReader: Layout {
    let log: RankLog

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        log.ranks = subviews.map { $0[Rank.self] }
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

/// The ranked words a `RankReader` reads.
@MainActor
private func rankedWords() -> some View {
    Group {
        Text("a").layoutValue(key: Rank.self, value: 5)
        Text("b")
    }
}

@MainActor
@Suite("A subview lays out as the view it stands for")
struct SubviewLayoutTraitsTests {

    private func render(_ view: some View, width: Int = 12, height: Int = 4) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    @Test("A proxied Spacer is a spacer: an ideal-width row keeps its minimum length")
    func spacerMinimumLength() {
        for minLength in [nil, 3] {
            let direct = render(HStack(spacing: 1) { spacedWords(minLength: minLength) }.fixedSize())
            let proxied = render(
                HStack(spacing: 1) { ForEach(subviews: spacedWords(minLength: minLength)) { $0 } }
                    .fixedSize())
            #expect(proxied == direct, "minLength \(String(describing: minLength))")
        }
    }

    @Test("A proxied Spacer fills the row as a spacer does")
    func spacerFills() {
        let direct = render(HStack(spacing: 1) { spacedWords() })
        let proxied = render(HStack(spacing: 1) { ForEach(subviews: spacedWords()) { $0 } })
        #expect(direct == ["a          b"])
        #expect(proxied == direct)
    }

    @Test("A proxied Spacer fills a column as a spacer does")
    func spacerFillsColumn() {
        let direct = render(VStack(spacing: 0) { spacedWords() }, width: 3, height: 5)
        let proxied = render(
            VStack(spacing: 0) { Group(subviews: spacedWords()) { $0[0]; $0[1]; $0[2] } },
            width: 3, height: 5)
        #expect(proxied == direct)
    }

    @Test("A member's alignment guide moves its proxy", arguments: [false, true])
    func guides(centered: Bool) {
        let alignment: HorizontalAlignment = centered ? .center : .leading
        let direct = render(VStack(alignment: alignment, spacing: 0) { guidedRows() }, width: 16)
        let proxied = render(
            VStack(alignment: alignment, spacing: 0) { ForEach(subviews: guidedRows()) { $0 } },
            width: 16)
        #expect(proxied == direct)
    }

    @Test("A guide written on the proxy wins over the member's")
    func proxyGuideWins() {
        let lines = render(
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subviews: guidedRows()) { $0.alignmentGuide(.leading) { _ in 0 } }
            }, width: 16)
        let trimmed = lines.prefix(3).map { String($0.reversed().drop { $0 == " " }.reversed()) }
        #expect(trimmed == ["wide row", "b", "c"])
    }

    @Test("A member's z-index orders its proxy, through a modifier on the proxy too")
    func zIndex() {
        let direct = render(ZStack { layeredWords() })
        let proxied = render(ZStack { ForEach(subviews: layeredWords()) { $0 } })
        let padded = render(ZStack { ForEach(subviews: layeredWords()) { $0.padding(0) } })
        #expect(direct.first == "top")
        #expect(proxied == direct)
        #expect(padded == direct)
    }

    @Test("A member's layout value reaches the Layout its proxy is placed in")
    func layoutValue() {
        let log = RankLog()
        _ = render(RankReader(log: log) { ForEach(subviews: rankedWords()) { $0 } })
        #expect(log.ranks == [5, -1])
    }

    @Test("A Layout reads a member's guide through its proxy")
    func layoutDimensions() {
        let captured = GuideLog()
        _ = render(GuideReader(log: captured) { ForEach(subviews: guidedRows()) { $0 } })
        #expect(captured.leading == [0, -2, 0])
    }

    @Test("A proxy for an ordinary view is no spacer and carries nothing")
    func ordinaryMember() {
        var proxies: [Subview] = []
        _ = render(
            Group(subviews: Group { Text("a"); Spacer() }) { subviews -> EmptyView in
                proxies = Array(subviews)
                return EmptyView()
            })
        let children = proxies.map { ChildView($0) }
        #expect(children.map(\.isSpacer) == [false, true])
        #expect(children.map(\.providesAlignmentGuide) == [false, false])
        #expect(children.map(\.zIndex) == [0, 0])
    }
}

/// Each subview's leading guide, as a `Layout` reads it.
@MainActor
private final class GuideLog {
    var leading: [Double] = []
}

private struct GuideReader: Layout {
    let log: GuideLog

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        log.leading = subviews.map { $0.dimensions(in: .unspecified)[.leading] }
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}
