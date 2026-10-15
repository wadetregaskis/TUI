//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpacerSpacingTests.swift
//
//  A `Spacer` asks for no space beside it, and with no `minLength` is never
//  shorter than one default gap, as SwiftUI's is (decisions A-BITEMS1-1; the
//  owner's ruling of 2026-10-13: "follow SwiftUI's example … it'll let the
//  buttons spread out, but it'll never force them to"). Measured on SwiftUI,
//  macOS 15 (`Tools/SwiftUIProbes/Stack spacing per pair/spacer.out`): a
//  spacer is 8 points at least, and `HStack { box; Spacer(); box }` at its
//  ideal width is 28 — the same as `HStack { box; box }`, two 10-point boxes
//  8 apart. Here the default gap in a row is one column, in a column none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("A spacer asks for no space and is one gap long at least")
struct SpacerSpacingTests {
    private func idealWidth<V: View>(_ view: V) -> Int {
        measureChild(view, proposal: .unspecified, context: makeRenderContext(width: 40, height: 3).askingIdealWidth())
            .width
    }

    private func drawn<V: View>(_ view: V, width: Int) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 3)).lines.first?.stripped ?? ""
    }

    @Test("A row with no room to spare is as wide with a spacer as without one (SwiftUI: box|spacer|box 28, box|box 28)")
    func spacerAddsNothingAtIdeal() {
        let withSpacer = idealWidth(HStack { Text("a"); Spacer(); Text("b") })
        let without = idealWidth(HStack { Text("a"); Text("b") })
        #expect(withSpacer == 3)
        #expect(withSpacer == without)
        #expect(drawn(HStack { Text("a"); Spacer(); Text("b") }, width: 3) == "a b")
    }

    @Test("A stated spacing stays beside a spacer, which is one gap long itself (SwiftUI: spacing 0 → 28, spacing 5 → 38)")
    func statedSpacingStays() {
        #expect(idealWidth(HStack(spacing: 0) { Text("a"); Spacer(); Text("b") }) == 3)
        #expect(idealWidth(HStack(spacing: 2) { Text("a"); Spacer(); Text("b") }) == 7)
    }

    @Test("A spacer of no minimum length lets its neighbours meet (SwiftUI: box|spacer(min 0)|box 20)")
    func zeroMinimumMeets() {
        #expect(idealWidth(HStack { Text("a"); Spacer(minLength: 0); Text("b") }) == 2)
    }

    @Test("With room to spare a spacer takes it, as before")
    func spacerTakesTheRoom() {
        #expect(drawn(HStack { Text("a"); Spacer(); Text("b") }, width: 10) == "a        b")
    }

    @Test("Squeezed, a spacer keeps its gap and the texts share the rest (SwiftUI: t10|spacer|t10 in 18 is 8, 1, 9)")
    func squeezedSpacerKeepsItsGap() {
        let row = drawn(
            HStack { Text("aaaa").lineLimit(1); Spacer(); Text("bbbb").lineLimit(1) }, width: 6)
        #expect(row == "aa… b…", "\(row)")
    }

    @Test("In a column a spacer's default length is none, the column's default gap")
    func columnUnchanged() {
        let lines = renderToBuffer(
            VStack(alignment: .leading) { Text("a"); Spacer(); Text("b") },
            context: makeRenderContext(width: 10, height: 2)
        ).lines.map(\.stripped)
        #expect(lines == ["a", "b"], "\(lines)")
    }

    @Test("A layout's spacer asks for no space too, and is a gap long")
    func layoutAgrees() {
        #expect(drawn(HStackLayout { Text("a"); Spacer(); Text("b") }, width: 3) == "a b")
        // What a `Layout` stack reads of a spacer: its own measure, a gap long
        // along the axis it is in, nothing across it.
        let context = makeRenderContext(width: 10, height: 3)
        let inRow = measureChild(Spacer(), proposal: ProposedSize(width: 0, height: 0), context: context.publishingContainerAxis(.horizontal))
        #expect(inRow.width == 1 && inRow.height == 0, "\(inRow)")
        let inColumn = measureChild(Spacer(), proposal: ProposedSize(width: 0, height: 0), context: context.publishingContainerAxis(.vertical))
        #expect(inColumn.width == 0 && inColumn.height == 0, "\(inColumn)")
    }
}
