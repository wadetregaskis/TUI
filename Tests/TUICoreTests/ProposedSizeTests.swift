//  🖥️ TUI — A Terminal UI framework for Swift
//  ProposedSizeTests.swift
//
//  `ProposedSize`, SwiftUI's `ProposedViewSize` in cells: `.zero` (the
//  semantic audit's item 113) beside `.unspecified`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("ProposedSize")
struct ProposedSizeTests {
    @Test(".zero proposes no space on either axis, and .unspecified none at all")
    func zeroAndUnspecified() {
        #expect(ProposedSize.zero == ProposedSize(width: 0, height: 0))
        #expect(ProposedSize.unspecified == ProposedSize(width: nil, height: nil))
        #expect(ProposedSize.zero != .unspecified)
    }
}
