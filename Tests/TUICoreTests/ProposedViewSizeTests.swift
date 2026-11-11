//  🖥️ TUI — A Terminal UI framework for Swift
//  ProposedViewSizeTests.swift
//
//  `ProposedViewSize`, SwiftUI's own type in cells: `.zero` (the
//  semantic audit's item 113) beside `.unspecified`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("ProposedViewSize")
struct ProposedViewSizeTests {
    @Test(".zero proposes no space on either axis, and .unspecified none at all")
    func zeroAndUnspecified() {
        #expect(ProposedViewSize.zero == ProposedViewSize(width: 0, height: 0))
        #expect(ProposedViewSize.unspecified == ProposedViewSize(width: nil, height: nil))
        #expect(ProposedViewSize.zero != .unspecified)
    }
}
