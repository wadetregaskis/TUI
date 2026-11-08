//  🖥️ TUI — A Terminal UI framework for Swift
//  ZStackLayoutFlexibilityTests.swift
//
//  `ZStackLayout` reported the size it measured and nothing of its layers'
//  flexibility, so a layer that fills (a `Color`) made a rigid layout of the
//  width it happened to be measured at, and a row could not share its slack
//  with it as it does with a `ZStack`. Like `ZStack` and the other two stack
//  layouts, it is now as flexible as its most flexible layer.
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
@Suite("ZStackLayout is as flexible as its layers")
struct ZStackLayoutFlexibilityTests {

    @Test("A filling layer makes the layout flexible on both axes")
    func reportsFlexibility() {
        let context = makeBareRenderContext(width: 20, height: 5)
        let size = measureChild(
            ZStackLayout { Color.red }, proposal: ProposedSize(width: 20, height: 5), context: context)
        #expect(size.isWidthFlexible && size.isHeightFlexible, "\(size)")
        let rigid = measureChild(
            ZStackLayout { Text("x") }, proposal: ProposedSize(width: 20, height: 5), context: context)
        #expect(!rigid.isWidthFlexible && !rigid.isHeightFlexible, "\(rigid)")
    }

    @Test("In a row, the layout shares the slack as a ZStack does")
    func rowMatchesZStack() {
        let context = makeBareRenderContext(width: 20, height: 1)
        let layout = renderToBuffer(HStack { ZStackLayout { Color.red }; Text("hi") }, context: context)
        let stack = renderToBuffer(HStack { ZStack { Color.red }; Text("hi") }, context: context)
        #expect(layout.lines.map(\.stripped) == stack.lines.map(\.stripped))
        #expect(layout.lines.first?.stripped.hasSuffix("hi") == true, "\(layout.lines.map(\.stripped))")
    }
}
