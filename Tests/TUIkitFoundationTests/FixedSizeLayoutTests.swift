//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FixedSizeLayoutTests.swift
//
//  `.fixedSize(horizontal:vertical:)` as a layout: the content at its ideal
//  size on the fixed axes, whatever it is offered there (DEVS #12; the
//  semantic audit's item 33). It used to set a flag only `List` read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("fixedSize as a layout")
struct FixedSizeLayoutTests {
    private func ctx(width: Int, height: Int = 10) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()).isolatingRenderCache()
    }

    private func lines(_ view: some View, width: Int, height: Int = 10) -> [String] {
        renderToBuffer(view, context: ctx(width: width, height: height)).lines.map(\.stripped)
    }

    @Test("A fixed Text keeps its ideal width: one line, where offered less it would wrap")
    func textKeepsIdealWidth() {
        let wrapped = lines(Text("a label of twenty-six cells"), width: 12)
        #expect(wrapped.count > 1, "unfixed, it wraps: \(wrapped)")
        let size = measureChild(Text("a label of twenty-six cells").fixedSize(), proposal: ProposedSize(width: 12, height: 10), context: ctx(width: 12))
        #expect(size.width == 27 && size.height == 1, "\(size)")
        #expect(!size.isWidthFlexible)
    }

    @Test("In a crowded HStack a fixed Text keeps its whole title and its neighbour takes the squeeze")
    func fixedNeighbourTakesTheSqueeze() {
        let row = HStack(alignment: .top, spacing: 1) {
            Text("Name:").fixedSize()
            Text("a value much too long to fit beside it")
        }
        let out = lines(row, width: 20)
        #expect(out.first?.hasPrefix("Name: ") == true, "\(out)")
        #expect(!out.contains { $0.hasPrefix("Nam") && !$0.hasPrefix("Name:") }, "the title is not cut: \(out)")
    }

    @Test("Fixed on one axis only: vertical alone leaves the width to the container")
    func verticalOnly() {
        let size = measureChild(
            Text("a label of twenty-six cells").fixedSize(horizontal: false, vertical: true),
            proposal: ProposedSize(width: 12, height: 10), context: ctx(width: 12))
        #expect(size.width <= 12 && size.height > 1, "\(size)")
    }

    @Test("Neither axis fixed is the content as it was")
    func neitherAxis() {
        let plain = lines(Text("a label of twenty-six cells"), width: 12)
        let unfixed = lines(Text("a label of twenty-six cells").fixedSize(horizontal: false, vertical: false), width: 12)
        #expect(plain == unfixed)
    }
}
