//  🖥️ TUI — A Terminal UI framework for Swift
//  ConditionalRecordTests.swift
//
//  What a conditional keeps of its last frame: the branch it took and what
//  of that is playing, and nothing it drew. Kept for every `if`/`else` drawn
//  whole on every frame, a picture was what made a nested page's footprint
//  grow with its depth times its area (`deep` 17.1 → 32.6 MB; decisions
//  TR2PERF), and a branch left with no transition of its own now goes at once
//  rather than fading out from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIView

@Suite("A conditional's record")
struct ConditionalRecordTests {
    @Test("A conditional's record keeps no picture: eight bytes, with no padding between its fields")
    func eightBytes() {
        #expect(MemoryLayout<ConditionalRecord>.size == 8)
        #expect(MemoryLayout<ConditionalRecord>.stride == 8)
    }
}
