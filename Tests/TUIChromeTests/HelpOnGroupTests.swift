//  🖥️ TUI — A Terminal UI framework for Swift
//  HelpOnGroupTests.swift
//
//  `.help(_:)` on a `Group` reaches each member, as SwiftUI's modifiers on a
//  `Group` do (S3-WRAPPERS): the members stay the enclosing stack's children.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIChrome
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Help on a Group")
struct HelpOnGroupTests {
    @Test("Help on a Group keeps the members side by side in a row")
    func helpOnGroupKeepsTheRowAxis() {
        let context = makeBareRenderContext(width: 30, height: 8)
        let plain = renderToBuffer(HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: context)
        let helped = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.help("both") }, context: context)
        // It drew the two as one column before 2026-10-18.
        #expect(helped.lines.count == 1)
        #expect(helped.lines.map(\.stripped) == plain.lines.map(\.stripped))
    }
}
