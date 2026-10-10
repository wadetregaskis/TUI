//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonSizingTests.swift
//
//  `.buttonSizing(.flexible)`: a button with a face widens it to the width it
//  is offered and centres its label; a plain one keeps its width; and the
//  default fits the label as it always did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Button sizing")
struct ButtonSizingTests {

    private func line(_ view: some View, width: Int = 20) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 3)).lines.first?.stripped ?? ""
    }

    @Test("A bordered button fills the width and centres its title")
    func borderedFills() {
        let drawn = line(Button("Open") {}.buttonStyle(.bordered).buttonSizing(.flexible))
        #expect(drawn.count == 20, "\(drawn.debugDescription)")
        let title = drawn.range(of: "Open")!
        let before = drawn.distance(from: drawn.startIndex, to: title.lowerBound)
        let after = drawn.distance(from: title.upperBound, to: drawn.endIndex)
        #expect(abs(before - after) <= 1, "centred: \(drawn.debugDescription)")
    }

    @Test("A view label fills too")
    func viewLabelFills() {
        let drawn = line(Button {} label: { Text("Go") }.buttonStyle(.bordered).buttonSizing(.flexible))
        #expect(drawn.count == 20, "\(drawn.debugDescription)")
    }

    @Test("Fitted and the default keep the label's width; a plain button has no face to widen")
    func fittedKeepsItsWidth() {
        let natural = line(Button("Open") {}.buttonStyle(.bordered))
        #expect(natural.count < 20)
        #expect(line(Button("Open") {}.buttonStyle(.bordered).buttonSizing(.fitted)) == natural)
        let plain = line(Button("Open") {}.buttonStyle(.plain))
        #expect(line(Button("Open") {}.buttonStyle(.plain).buttonSizing(.flexible)) == plain)
    }

    @Test("A flexible button measures as filling what it is offered")
    func measuresFlexible() {
        let size = measureChild(
            Button("Open") {}.buttonStyle(.bordered).buttonSizing(.flexible),
            proposal: ProposedSize(width: 30, height: 1),
            context: makeRenderContext(width: 30, height: 1))
        #expect(size.width == 30 && size.isWidthFlexible)
    }
}
