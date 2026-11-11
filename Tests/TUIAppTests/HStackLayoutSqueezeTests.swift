//  🖥️ TUI — A Terminal UI framework for Swift
//  HStackLayoutSqueezeTests.swift
//
//  `HStackLayout` measured each subview once, at its ideal width, and took the
//  row's height from those answers. A subview squeezed narrower than its ideal
//  was then placed at the narrower width but the ideal's height, so a text
//  that wrapped in the room it was given lost every line after the first.
//  `HStack` re-measures a squeezed child at the width it is given, as SwiftUI
//  does; the layout value now does too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore
import TUIView

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("HStackLayout re-measures a squeezed subview")
struct HStackLayoutSqueezeTests {

    private func lines(_ view: some View, width: Int = 20, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map { $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    @Test("A wrapped text keeps all its lines, as in an HStack")
    func wrappedTextKeepsItsLines() {
        let long = "alpha beta gamma delta epsilon"
        let layout = lines(HStackLayout { Text(long); Text("TAIL") })
        let stack = lines(HStack(alignment: .top) { Text(long); Text("TAIL") })
        #expect(layout.joined(separator: " ").contains("epsilon"), "\(layout)")
        #expect(layout == stack, "layout \(layout) against stack \(stack)")
    }

    @Test("The row reports the squeezed subview's wrapped height")
    func measuredHeight() {
        let context = makeBareRenderContext(width: 20, height: 10)
        let size = measureChild(
            HStackLayout { Text("alpha beta gamma delta epsilon"); Text("TAIL") },
            proposal: ProposedViewSize(width: 20, height: nil), context: context)
        #expect(size.height > 1, "\(size)")
    }

    @Test("Through AnyLayout as well")
    func throughAnyLayout() {
        let layout = lines(AnyLayout(HStackLayout()) { Text("alpha beta gamma delta epsilon"); Text("TAIL") })
        #expect(layout.joined(separator: " ").contains("epsilon"), "\(layout)")
    }
}
