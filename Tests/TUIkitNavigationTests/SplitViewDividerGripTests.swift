//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewDividerGripTests.swift
//
//  An HSplitView's or a VSplitView's divider draws a grip — three `◦` at the
//  middle of its rule — unless `.splitViewDividerGrip(.hidden)` says not to.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitNavigation
@testable import TUIkitTestSupport

@MainActor
@Suite("Split view divider grips")
struct SplitViewDividerGripTests {
    private func horizontal() -> some View {
        HSplitView {
            Text("left").frame(maxWidth: .infinity)
            Text("right").frame(maxWidth: .infinity)
        }
    }

    /// The divider's column, top to bottom.
    private func dividerColumn(_ buffer: FrameBuffer) -> String {
        let lines = buffer.lines.map(\.stripped)
        guard let first = lines.first, let index = first.firstIndex(where: { $0 == "│" || $0 == "◦" }) else {
            return ""
        }
        let offset = first.distance(from: first.startIndex, to: index)
        return String(lines.compactMap { line in line.dropFirst(offset).first })
    }

    @Test("An HSplitView's divider draws three ◦ at its middle")
    func horizontalGrip() {
        let drawn = InputChainHarness(width: 20, height: 7).frame(horizontal())
        #expect(dividerColumn(drawn) == "││◦◦◦││", "\(drawn.lines.map(\.stripped))")
    }

    @Test("A VSplitView's divider draws them across its rule")
    func verticalGrip() {
        let drawn = InputChainHarness(width: 9, height: 6).frame(
            VSplitView {
                Text("top").frame(maxHeight: .infinity)
                Text("bottom").frame(maxHeight: .infinity)
            })
        let rule = drawn.lines.map(\.stripped).first { $0.contains("─") || $0.contains("◦") }
        #expect(rule == "───◦◦◦───", "\(drawn.lines.map(\.stripped))")
    }

    @Test(".splitViewDividerGrip(.hidden) leaves the plain rule")
    func hidden() {
        let drawn = InputChainHarness(width: 20, height: 7).frame(horizontal().splitViewDividerGrip(.hidden))
        #expect(dividerColumn(drawn) == "│││││││", "\(drawn.lines.map(\.stripped))")
    }
}
