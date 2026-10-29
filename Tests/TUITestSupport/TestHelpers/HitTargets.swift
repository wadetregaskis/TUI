//  🖥️ TUI — A Terminal UI framework for Swift
//  HitTargets.swift
//
//  A buffer's hit-test TARGETS: its regions less the text frames each `Text`
//  files for the screen selection (`HitTestRegion.HandlerID.textFrame`), which
//  ride in the same array but take no event. What a suite asking where clicks
//  land counts.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUICore

extension FrameBuffer {
    /// The hit-test regions an event can land on: every region but the text
    /// frames.
    package var hitTargets: [HitTestRegion] { hitTestRegions.filter { !$0.isTextFrame } }
}

#endif
