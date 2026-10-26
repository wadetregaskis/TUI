//  🖥️ TUI — A Terminal UI framework for Swift
//  ListScrollbarSpacingTests.swift
//
//  `.scrollbarSpacing(_:)` on a `List`: the cells its rows keep clear of the
//  vertical scrollbar — one unless stated. The rows are laid out before the
//  list knows whether it overflows, so the bar is predicted, and a frame
//  that predicted wrong asks for the next one, which is right.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("A list's spacing before its scrollbar")
struct ListScrollbarSpacingTests {

    private static let items = (0..<12).map { "item \($0)" }

    /// A list whose rows put a "9" at their trailing edge, as a badge would.
    private func list(_ visibility: ScrollIndicatorVisibility, spacing: Int? = nil) -> some View {
        let list = List(Self.items, id: \.self) { item in
            HStack {
                Text(item)
                Spacer()
                Text("9")
            }
        }
        .scrollIndicators(visibility)
        return Group {
            if let spacing { list.scrollbarSpacing(spacing) } else { list }
        }
    }

    /// The cells between the trailing "9" and the bar on the line with `arrow`.
    private func gap(_ buffer: FrameBuffer, arrow: Character = "▲") throws -> Int {
        let line = Array(try #require(buffer.lines.map(\.stripped).first { $0.contains(arrow) }))
        let bar = try #require(line.firstIndex(of: arrow))
        let nine = try #require(line[..<bar].lastIndex(of: "9"))
        return bar - nine - 1
    }

    @Test("A visible bar is kept one cell clear of the rows from the first frame, or as stated")
    func visibleBar() throws {
        for (spacing, expected) in [(nil, 1), (0, 0), (3, 3)] as [(Int?, Int)] {
            let buffer = renderToBuffer(list(.visible, spacing: spacing), context: makeRenderContext(width: 30, height: 8))
            #expect(try gap(buffer) == expected, "spacing \(String(describing: spacing)): \(buffer.lines.map(\.stripped))")
        }
    }

    @Test("An automatic bar the first frame did not predict is right from the next")
    func automaticBarSettles() throws {
        let context = makeRenderContext(width: 30, height: 8)
        _ = renderToBuffer(list(.automatic), context: context)
        let second = renderToBuffer(list(.automatic), context: context)
        #expect(try gap(second) == 1, "\(second.lines.map(\.stripped))")
    }
}
